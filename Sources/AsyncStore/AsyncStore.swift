//
//  AsyncStore.swift
//
//
//  Created by Wendell Thompson (AO) on 2/14/22.
//

import Foundation
import SwiftUI

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
    
    public init(state: State, env: Environment, mapError: @escaping (Error) -> Effect) {
        self._state = state
        self._env = env
        self._mapError = mapError
        
        let stream = AsyncStream<Effect>(
            Effect.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            self.receiveContinuation = continuation
        }
        
        self.receiveTask = Task {
            for await effect in stream {
                await reduce(effect)
            }
        }
    }
    
    deinit {
        receiveContinuation?.finish()
        receiveTask?.cancel()
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
    
    public func receive(_ effect: Effect) {
        let result = receiveContinuation?.yield(effect)
        switch result {
        case .dropped(let effect):
            AsyncStoreLog.warning("[\(type(of: self))] dropped received effect \(effect)")
        case .terminated:
            AsyncStoreLog.warning("[\(type(of: self))] stream terminated")
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
            await cancelStore.store(id, cancel: task.cancel)
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
                for try await date in timer {
                    let effect = mapEffect(date)
                    await reduce(effect)
                }
            }
            await cancelStore.store(id, cancel: timerTask.cancel)
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
            await cancelStore.store(id, cancel: debounceTask.cancel)
            guard awaitTask else { return }
            await debounceTask.value
        case .cancel(let id):
            await cancelStore.cancel(id)
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

extension AsyncStore {
    private func execute(_ operation: () async throws -> Effect) async -> Effect {
        do {
            return try await operation()
        } catch let error {
            return _mapError(error)
        }
    }
    
    @MainActor private func setOnMain(_ setter: @escaping (inout State) -> Void) async {
        objectWillChange(setter)
    }
    
    private func objectWillChange(_ setter: @escaping (inout State) -> Void) {
        objectWillChange.send()
        setter(&_state)
        stateDistributor.yield(_state)
    }
    
    private func downstream(for id: AnyHashable) -> AsyncStream<State> {
        stateDistributor.stream(for: id, initialValue: _state, bufferingPolicy: .bufferingNewest(1))
    }
    
    private func bindTask(for effectStream: AnyAsyncSequence<Effect>) -> Task<Void, Never> {
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
    
    private func processWarnings(for effect: Effect) {
        switch effect {
        case .concatenate(let effects) where effects.contains(where: { $0.isDebounce }):
            AsyncStoreLog.warning("[\(type(of: self))] Concatenated debounce effects may not be debounced as they will be synchronized.")
        default:
            break
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
        let effectStream = downstream(for: id)
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .map(mapEffect)
        
        Task {
            let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
            await cancelStore.store(id, cancel: bindTask.cancel)
        }
    }
    
    func bind<Value, Stream: AsyncSequence>(
        id: AnyHashable,
        to stream: Stream,
        mapEffect: @escaping (Value) -> Effect
    ) where Value: Equatable, Stream.Element == Value{
        let effectStream = stream
            .removeDuplicates()
            .map(mapEffect)
        
        Task {
            let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
            await cancelStore.store(id, cancel: bindTask.cancel)
        }
    }
    
    func bind<UState, UEnv, Value>(
        id: AnyHashable,
        to upstreamStore: AsyncStore<UState, UEnv>,
        on keyPath: KeyPath<UState, Value>,
        mapEffect: @escaping (Value) -> Effect
    ) where Value: Equatable {
        let effectStream = upstreamStore.downstream(for: id)
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .map(mapEffect)
        
        Task {
            let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
            await cancelStore.store(id, cancel: bindTask.cancel)
        }
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
