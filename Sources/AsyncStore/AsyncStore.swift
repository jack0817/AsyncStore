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
    public fileprivate(set) var state: State
    
    @ObservationIgnored
    public var mapError: (@Sendable (any Error) -> Effect) = { _ in .none }
    
    @ObservationIgnored
    private var runContinuation: AsyncStream<Effect>.Continuation? = .none
    
    @ObservationIgnored
    private var runTask: Task<Void, Never>? = .none
    
    @ObservationIgnored
    private var tasks: [TaskIdentifier: Task<Effect, Never>] = [:]
    
    @ObservationIgnored
    private var repoTasks: [Int: Task<Void, Never>] = [:]
    
    @ObservationIgnored
    private var stateContinuations: [AsyncStream<State>.Continuation] = []
    
    @ObservationIgnored
    public let env: AsyncStoreEnvironmentValues
    
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
    
    isolated deinit {
        runContinuation?.finish()
        runTask?.cancel()
        tasks.values.forEach { $0.cancel() }
        stateContinuations.forEach { $0.finish() }
        unbindAll()
    }
    
    public subscript<Value>(dynamicMember property: KeyPath<State, Value>) -> Value {
        get { state[keyPath: property] }
    }
}

// MARK: Public API

public extension AsyncStore {
    func run(_ effect: Effect) {
        runContinuation?.yield(effect)
    }
    
    func binding<Value: Sendable & Equatable>(
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
    
    func bind<Key: AsyncStoreRepositoryKey, Value: Equatable & Sendable>(
        _ repoKey: Key.Type,
        to keyPath: KeyPath<Key.State, Value>,
        map: @escaping (Value) -> Effect
    ) {
        let stream = AsyncStoreRepository.shared[repoKey]
            .stream(for: keyPath)
            .removeDuplicates()
        
        let repoTask = Task { [weak self] in
            for await value in stream {
                let effect = map(value)
                _ = await MainActor.run {
                    self?.runContinuation?.yield(effect)
                }
            }
        }
        
        let repoTaskId = repoTaskId(for: repoKey, keyPath: keyPath)
        repoTasks[repoTaskId] = repoTask
    }
    
    func repo<Key: AsyncStoreRepositoryKey, Value>(
        for key: Key.Type,
        _ keyPath: KeyPath<Key.State, Value>
    ) -> Value {
        AsyncStoreRepository.shared[key].state[keyPath: keyPath]
    }
}

// MARK: Internal API

internal extension AsyncStore {
    func stream<Value: Equatable & Sendable>(
        for keyPath: KeyPath<State, Value>
    ) ->  AsyncMapSequence<AsyncStream<State>, Value> {
        let stateStream = AsyncStream<State> { continuation in
            stateContinuations.append(continuation)
            continuation.yield(state)
        }
        
        return stateStream.map { $0[keyPath: keyPath] }
    }
    
    func unbindAll() {
        repoTasks.keys.forEach { repoTasks[$0]?.cancel() }
        repoTasks.removeAll()
    }
}

// MARK: Private API

fileprivate extension AsyncStore {
    func perform(_ setter: (inout State) -> Void) {
        setter(&_state)
        yieldState()
    }
    
    func execute(
        _ operation: @Sendable @escaping () async throws -> Effect,
        id: TaskIdentifier?
    ) async -> Effect {
        let opTask = Task.detached(priority: .background) {
            do {
                async let effectTask = operation()
                return try await effectTask
            } catch {
                return await MainActor.run { [weak self] in
                    self?.mapError(error) ?? .none
                }
            }
        }
        
        track(opTask, id: id)
        let effect = await opTask.value
        unTrack(id: id)
        return effect
    }
    
    func track(_ task: Task<Effect, Never>, id: TaskIdentifier?) {
        guard let id else { return }
        tasks[id]?.cancel()
        tasks[id] = task
    }
    
    func unTrack(id: TaskIdentifier?) {
        guard let id else { return }
        tasks[id] = .none
    }
    
    func yieldState() {
        var activeContinuations: [AsyncStream<State>.Continuation] = []

        stateContinuations.forEach { continuation in
            switch continuation.yield(state) {
            case .terminated:
                return
            default:
                activeContinuations.append(continuation)
            }
        }
        
        stateContinuations = activeContinuations
    }
    
    func repoTaskId<Key: AsyncStoreRepositoryKey, Value>(
        for key: Key.Type,
        keyPath: KeyPath<Key.State, Value>
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(self).hashValue)
        hasher.combine(ObjectIdentifier(key).hashValue)
        hasher.combine(keyPath.hashValue)
        return hasher.finalize()
    }
}

// MARK: Reduce

fileprivate extension AsyncStore {
    func reduce(_ effect: Effect) async {
        switch effect {
        case .none:
            return
        case .set(let setter):
            perform(setter)
        case .task(let operation, let id):
            let effect = await execute(operation, id: id)
            runContinuation?.yield(effect)
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
}
