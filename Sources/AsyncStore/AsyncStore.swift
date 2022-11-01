//
//  AsyncStore.swift
//
//
//  Created by Wendell Thompson (AO) on 2/14/22.
//

import Foundation
import Combine
import SwiftUI
import Atomics

// MARK: Store

@dynamicMemberLookup
public final class AsyncStore<State, Environment>: ObservableObject {
    private var _state: State
    private let _env: Environment
    private let _mapError: (Error) -> Effect
    
    private var receiveContinuation: AsyncStream<Effect>.Continuation? = .none
    private var receiveTask: Task<Void, Never>? = .none
    private let cancelStore = AsyncCancelStore()
    private let stateDistributor = AsyncDistributor<State>()
    
    private let stateChangedSubject = PassthroughSubject<Void, Never>()
    private var stateChangedSubscription: AnyCancellable? = .none
    private let _isActive = ManagedAtomic<Bool>(false)
    private var logTag: String { "[\(type(of: self))]" }
    
    public init(state: State, env: Environment, mapError: @escaping (Error) -> Effect) {
        self._state = state
        self._env = env
        self._mapError = mapError
        self.activate()
    }
    
    deinit {
        stateChangedSubscription?.cancel()
        receiveContinuation?.finish()
        receiveTask?.cancel()
        stateDistributor.finishAll()
        cancelStore.cancellAll()
    }
    
    public var isActive: Bool {
        _isActive.load(ordering: .sequentiallyConsistent)
    }
    
    public var state: State {
        get { _state }
    }
    
    public var env: Environment {
        get { _env }
    }
    
    public subscript <Value>(dynamicMember dynamicMember: KeyPath<State, Value>) -> Value {
        get { _state[keyPath: dynamicMember] }
    }
    
    public func activate() {
        stateChangedSubscription?.cancel()
        stateChangedSubscription = stateChangedSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        
        receiveContinuation?.finish()
        let stream = AsyncStream<Effect>(
            Effect.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            self.receiveContinuation = continuation
        }
        
        receiveTask?.cancel()
        receiveTask = Task {
            for await effect in stream {
                await reduce(effect)
            }
        }
        
        setIsActive(to: true)
    }
    
    public func deactivate() {
        receiveTask?.cancel()
        stateDistributor.finishAll()
        cancelStore.cancellAll()
        setIsActive(to: false)
        AsyncStoreLog.debug("\(logTag) deactivated")
    }
    
    public func receive(_ effect: Effect) {
        guard _isActive.load(ordering: .sequentiallyConsistent) else {
            AsyncStoreLog.warning("\(logTag) is deactivated")
            return
        }
        
        checkMainThread("\(logTag) 'receive' should only be called from the main thread")

        let result = receiveContinuation?.yield(effect)
        switch result {
        case .dropped(let effect):
            AsyncStoreLog.warning("\(logTag) dropped received effect \(effect)")
        case .terminated:
            AsyncStoreLog.warning("\(logTag) stream terminated")
        default:
            break
        }
    }
    
    public func binding<Value>(for keyPath: WritableKeyPath<State, Value>) -> Binding<Value> {
        let defaultValue = _state[keyPath: keyPath]
        return .init(
            get: { [weak self] in
                guard let self = self else { return defaultValue }
                return self._state[keyPath: keyPath]
            },
            set: { [weak self] value in
                guard let self = self else { return }
                self.objectWillChange { $0[keyPath: keyPath] = value }
            }
        )
    }
    
    public func stream<Value: Equatable>(
        for id: AnyHashable,
        at keyPath: KeyPath<State, Value>,
        bufferingPolicy: AsyncDistributor<State>.BufferingPolicy = .unbounded
    ) -> AnyAsyncSequence<Value> {
        stateDistributor.stream(
            for: id,
            initialValue: state,
            bufferingPolicy: bufferingPolicy
        )
        .map{ $0[keyPath: keyPath] }
        .removeDuplicates()
        .eraseToAnyAsyncSequence()
    }
}

// MARK: Reducer

extension AsyncStore {
    private func reduce(_ effect: Effect, awaitTask: Bool = false) async {
        processWarnings(for: effect)
        
        switch effect {
        case .none:
            break
        case .set(let setter):
            await setOnMain(setter)
        case .task(let operation, let id):
            let task = Task {
                let effect = await execute(operation)
                await reduce(effect)
            }
            cancelStore.store(id, task: task)
            guard awaitTask else { return }
            await task.value
        case .sleep(let time):
            do {
                try await Task.trySleep(for: time)
            } catch let error {
                let effect = _mapError(error)
                await reduce(effect)
            }
        case .timer(let interval, let id, let mapEffect):
            let timer = AsyncTimer(interval: interval)
            let timerTask = Task {
                for await date in timer {
                    let effect = mapEffect(date)
                    await reduce(effect)
                }
            }
            cancelStore.store(id, task: timerTask)
        case .debounce(let operation, let id, let delay):
            let parentTask: Task<Task<Void, Never>, Never> = Task {
                Task {
                    let effect = await execute {
                        try await Task.trySleep(for: delay)
                        return try await operation()
                    }
                    await reduce(effect)
                }
            }
            let debounceTask = await parentTask.value
            cancelStore.store(id, task: debounceTask)
            guard awaitTask else { return }
            await debounceTask.value
        case .cancel(let id):
            cancelStore.cancel(id)
        case .merge(let effects):
            let mergeStream = AsyncStream<Void> { cont in
                effects.forEach { effect in
                    Task {
                        await reduce(effect)
                        cont.yield(())
                    }
                }
            }
            
            var mergeCount = 0
            for await _ in mergeStream {
                mergeCount += 1
                guard mergeCount < effects.count else { break }
            }
        case .concatenate(let effects):
            for effect in effects {
                await reduce(effect, awaitTask: true)
            }
        }
    }
}

// MARK: Private API

fileprivate extension AsyncStore {
    func execute(_ operation: () async throws -> Effect) async -> Effect {
        do {
            return try await operation()
        } catch let error {
            return _mapError(error)
        }
    }
    
    @MainActor func setOnMain(_ setter: @escaping (inout State) -> Void) async {
        objectWillChange(setter)
    }
    
    func objectWillChange(_ setter: @escaping (inout State) -> Void) {
        stateChangedSubject.send()
        setter(&_state)
        stateDistributor.yield(_state)
    }
    
    func downstream(for id: AnyHashable) -> AsyncStream<State> {
        stateDistributor.stream(for: id, initialValue: _state, bufferingPolicy: .unbounded)
    }
    
    func bindTask(for effectStream: AnyAsyncSequence<Effect>) -> Task<Void, Never> {
        Task {
            do {
                for try await effect in effectStream {
                    await reduce(effect)
                }
            } catch let error {
                let effect = _mapError(error)
                await reduce(effect)
            }
        }
    }
    
    func checkMainThread(_ warningMessage: String) {
        guard !Thread.current.isMainThread else { return }
        AsyncStoreLog.warning(warningMessage)
    }
    
    func processWarnings(for effect: Effect) {
        switch effect {
        case .concatenate(let effects) where effects.contains(where: { $0.isDebounce }):
            AsyncStoreLog.warning("\(logTag) Concatenated debounce effects may not be debounced as they will be synchronized.")
        default:
            break
        }
    }
    
    func setIsActive(to isActive: Bool) {
        let currentValue = _isActive.load(ordering: .sequentiallyConsistent)
        guard currentValue != isActive else { return }
        var isExchanged = false
        while !isExchanged {
            isExchanged = _isActive.compareExchange(
                expected: currentValue,
                desired: isActive,
                ordering: .sequentiallyConsistent
            ).exchanged
        }
    }
}

// MARK: Binding

public extension AsyncStore {
    func bind<Value>(
        id: AnyHashable,
        to keyPath: KeyPath<State, Value>,
        mapEffect: @escaping (Value) -> Effect
    ) where Value: Equatable {
        AsyncStoreLog.info("[\(type(of: self))] binding to id: \(id)")
        let effectStream = downstream(for: id)
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .map(mapEffect)
        
        let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
        cancelStore.store(id, task: bindTask)
    }
    
    func bind<Value, Stream: AsyncSequence>(
        id: AnyHashable,
        to stream: Stream,
        mapEffect: @escaping (Value) -> Effect
    ) where Value: Equatable, Stream.Element == Value{
        AsyncStoreLog.info("[\(type(of: self))] binding to id: \(id)")
        let effectStream = stream
            .removeDuplicates()
            .map(mapEffect)
        
        let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
        cancelStore.store(id, task: bindTask)
    }
    
    func bind<UState, UEnv, Value>(
        id: AnyHashable,
        to upstreamStore: AsyncStore<UState, UEnv>,
        on keyPath: KeyPath<UState, Value>,
        mapEffect: @escaping (Value) -> Effect
    ) where Value: Equatable {
        AsyncStoreLog.info("[\(type(of: self))] binding to id: \(id)")
        let effectStream = upstreamStore.downstream(for: id)
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .map(mapEffect)
        
        let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
        cancelStore.store(id, task: bindTask)
    }
}

// MARK: Effect Extensions

private extension AsyncStore.Effect {
    var isDebounce: Bool {
        switch self {
        case .debounce:
            return true
        default:
            return false
        }
    }
}
