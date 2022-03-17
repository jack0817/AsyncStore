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
    private let cancelActor = CancelActor()
    private let continuationActor = ContinuationActor<State>()
    private let stateDistributor = AsyncDistributor<State>()
    
    public init(state: State, env: Environment, mapError: @escaping (Error) -> Effect) {
        self._state = state
        self._env = env
        self._mapError = mapError
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
        Task { await reduce(effect) }
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
}

// MARK: Reducer

extension AsyncStore {
    private func reduce(_ effect: Effect) async {
        switch effect {
        case .none:
            break
        case .set(let setter):
            await setOnMain(setter)
        case .task(let operation, let id):
            await cancelActor.cancel(id)
            let task = Task {
                let effect = await execute(operation)
                await reduce(effect)
            }
            await cancelActor.store(id, cancel: task.cancel)
            await task.value
        case .sleep(let time):
            do {
                try await Task.trySleep(for: time)
            } catch let error {
                let effect = _mapError(error)
                await reduce(effect)
            }
        case .cancel(let id):
            await cancelActor.cancel(id)
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
                await reduce(effect)
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
        Task { await stateDistributor.yield(_state) }
    }
    
    private func createDownstream() -> (stream: AsyncStream<State>, finish: () -> Void) {
        let id = UUID().uuidString
        let finish = { [weak self] in
            guard let self = self else { return }
            Task { await self.stateDistributor.finish(id) }
        }
        
        let stream = AsyncStream<State> { cont in
            Task { await continuationActor.store(id, continuation: cont) }
            cont.yield(_state)
        }
        
        return (stream, finish)
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
}

// MARK: Binding

public extension AsyncStore {
    func bind<Value>(
        id: AnyHashable,
        to keyPath: KeyPath<State, Value>,
        mapEffect: @escaping (Value) -> Effect
    ) async where Value: Equatable {
        let stream = await stateDistributor.stream(for: id, .bufferingNewest(1))
        let effectStream = stream
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .map(mapEffect)
        
        let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
        Task { await cancelActor.store(id, cancel: bindTask.cancel) }
    }
    
    func bind<Value, Stream: AsyncSequence>(
        id: AnyHashable,
        to stream: Stream,
        mapEffect: @escaping (Value) -> Effect
    ) where Value: Equatable, Stream.Element == Value{
        let effectStream = stream
            .removeDuplicates()
            .map(mapEffect)
        
        let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
        Task { await cancelActor.store(id, cancel: bindTask.cancel) }
    }
    
    func bind<UState, UEnv, Value>(
        id: AnyHashable,
        to upstreamStore: AsyncStore<UState, UEnv>,
        on keyPath: KeyPath<UState, Value>,
        mapEffect: @escaping (Value) -> Effect
    ) async where Value: Equatable {
        let upstream = await upstreamStore.stateDistributor.stream(for: id, .bufferingNewest(1))
        let effectStream = upstream
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .map(mapEffect)
        
        let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
        Task { await cancelActor.store(id, cancel: bindTask.cancel) }
    }
}

public extension AsyncStore {
    @available(*, deprecated, message: "Use the async version of this func")
    func bind<Value>(
        id: AnyHashable,
        to keyPath: KeyPath<State, Value>,
        mapEffect: @escaping (Value) -> Effect
    ) where Value: Equatable {
        let stream = createDownstream()
        let effectStream = stream.stream
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .map(mapEffect)
        
        let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
        Task { await cancelActor.store(id, cancel: bindTask.cancel) }
    }
    
    @available(*, deprecated, message: "Use the async version of this func")
    func bind<UState, UEnv, Value>(
        id: AnyHashable,
        to upstreamStore: AsyncStore<UState, UEnv>,
        on keyPath: KeyPath<UState, Value>,
        mapEffect: @escaping (Value) -> Effect
    ) where Value: Equatable {
        let upstream = upstreamStore.createDownstream()
        let effectStream = upstream.stream
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .map(mapEffect)
        
        let bindTask = bindTask(for: effectStream.eraseToAnyAsyncSequence())
        Task { await cancelActor.store(id, cancel: bindTask.cancel) }
    }
}
