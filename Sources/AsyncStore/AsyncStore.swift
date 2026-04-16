//
//  AsyncStore.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/15/25.
//

import AsyncAlgorithms
import Foundation
import SwiftUI

@Observable
@MainActor
@dynamicMemberLookup
public final class AsyncStore<State: Sendable, TaskIdentifier: Hashable & Sendable> {
    public var state: State
    
    @ObservationIgnored
    public var mapError: (@Sendable (any Error) -> Effect)? = .none
    
    @ObservationIgnored
    private var runContinuation: AsyncStream<Effect>.Continuation? = .none
    
    @ObservationIgnored
    private var runTask: Task<Void, Never>? = .none
    
    @ObservationIgnored
    private var tasks: [TaskIdentifier: Task<Effect, Never>] = [:]
    
    @ObservationIgnored
    private var stateContinuations: [UUID: AsyncStream<State>.Continuation] = [:]
    
    @ObservationIgnored
    public let env: AsyncStoreEnvironmentValues
    
    public var repo: AsyncStoreEnvironmentValues { .shared }
    
    public init(state: State, environment: AsyncStoreEnvironmentValues = .shared) {
        self.state = state
        self.env = environment
        
        let runStream = AsyncStream<Effect> { continuation in
            self.runContinuation = continuation
        }
        
        runTask = Task(priority: .background) { [weak self] in
            for await effect in runStream {
                guard !Task.isCancelled, let self else { break }
                await self.reduce(effect)
            }
        }
    }
    
    deinit {
        runContinuation?.finish()
        runTask?.cancel()
        tasks.values.forEach { $0.cancel() }
        stateContinuations.values.forEach { $0.finish() }
        print("[AsyncStore<\(String(reflecting: Self.self)), \(String(reflecting: TaskIdentifier.self))>] deinit")
    }
    
    public subscript<Value>(dynamicMember property: KeyPath<State, Value>) -> Value {
        get { state[keyPath: property] }
    }
    
    public func run(_ effect: Effect) {
        runContinuation?.yield(effect)
    }
    
    public func binding<Value: Sendable & Equatable>(
        for property: WritableKeyPath<State, Value>
    ) -> Binding<Value> {
        let defaultValue = state[keyPath: property]
        return .init(
            get: { [weak self] in self?.state[keyPath: property] ?? defaultValue },
            set: { [weak self] in
                self?.state[keyPath: property] = $0
                self?.yieldState()
            }
        )
    }
    
    public func stream<Value: Equatable & Sendable>(
        for keyPath: KeyPath<State, Value>
    ) -> AnyAsyncSequence<Value> {
        let stateStream = AsyncStream<State> { continuation in
            stateContinuations[.init()] = continuation
            continuation.yield(state)
        }
        
        return stateStream
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }
    
    public func bind<Key: AsyncStoreRepositoryKey, Value: Sendable & Equatable>(
        to repoKey: Key,
        on property: KeyPath<Key.State, Value>,
        map: @escaping (Value) -> Effect
    ) {
        let stream = AsyncStoreRepository.shared[Key.self]
            .stream(for: property)
            .removeDuplicates()
        
        Task {
            for await value in stream {
                let effect = map(value)
                run(effect)
            }
        }
    }
    
    public func bind<OtherState, TaskId, Value: Sendable & Equatable>(
        to storeKeyPath: KeyPath<AsyncStoreRepository, AsyncStore<OtherState, TaskId>>,
        on property: KeyPath<OtherState, Value>,
        map: @escaping (Value) -> Effect
    ) {
        let stream = AsyncStoreRepository.shared[keyPath: storeKeyPath]
            .stream(for: property)
            .removeDuplicates()
        
        Task {
            for await value in stream {
                let effect = map(value)
                run(effect)
            }
        }
    }
}

fileprivate extension AsyncStore {
    func reduce(_ effect: Effect) async {
        switch effect {
        case .none:
            return
        case .set(let setter):
            setter(&state)
            yieldState()
        case .task(let operation, let id):
            let handleError = mapError ?? { _ in .none }
            let task = Task.detached(priority: .background) {
                do {
                    async let effect = operation()
                    return try await effect
                } catch {
                    return handleError(error)
                }
            }
            track(task, id: id)
            let effect = await task.value
            await reduce(effect)
        case .concatenate(let effects):
            for effect in effects {
                await reduce(effect)
            }
        case .merge(let effects):
            await withTaskGroup { group in
                for effect in effects {
                    group.addTask { @Sendable @MainActor [weak self] in
                        guard !Task.isCancelled else { return }
                        await self?.reduce(effect)
                    }
                }
            }
        }
    }
    
    func track(_ task: Task<Effect, Never>, id: TaskIdentifier?) {
        guard let id else { return }
        tasks[id]?.cancel()
        tasks[id] = task
    }
    
    func yieldState() {
        var terminatedIds: [UUID] = []

        stateContinuations.forEach { id, continuation in
            switch continuation.yield(state) {
            case .terminated:
                terminatedIds.append(id)
            default:
                break
            }
        }
        
        terminatedIds.forEach { id in
            stateContinuations[id]?.finish()
            stateContinuations[id] = .none
        }
    }
}
