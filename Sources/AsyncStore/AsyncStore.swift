//
//  AsyncStore.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/15/25.
//

import AsyncAlgorithms
import Foundation
import SwiftUI

/// A generic, observable state container that drives SwiftUI views through a unidirectional data flow.
///
/// `AsyncStore` holds a single ``state`` value and accepts ``Effect`` values via ``run(_:)`` to mutate
/// that state. Effects can set state synchronously, perform async work off the main thread, or compose
/// multiple operations sequentially or concurrently.
///
/// The store is `@Observable`, so SwiftUI views that read its properties re-render automatically.
/// It also supports `@dynamicMemberLookup`, letting you access state properties directly on the store
/// (e.g., `store.name` instead of `store.state.name`).
///
/// - Parameters:
///   - State: The `Sendable` value type that holds your feature's data.
///   - TaskIdentifier: A `Hashable & Sendable` type used to identify and cancel in-flight async tasks.
@Observable
@MainActor
@dynamicMemberLookup
public final class AsyncStore<State: Sendable, TaskIdentifier: Hashable & Sendable> {
    /// The current state value. Mutations trigger SwiftUI view updates.
    public fileprivate(set) var state: State
    
    /// A closure that maps errors thrown inside `.task` effects into new effects.
    ///
    /// By default, errors are mapped to ``Effect/none``. Assign a custom closure to convert
    /// errors into state mutations — for example, setting an error message property.
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
    /// The environment values available to this store, used for dependency injection.
    public let env: AsyncStoreEnvironmentValues
    
    /// Creates a new store with the given initial state and optional environment.
    ///
    /// - Parameters:
    ///   - state: The initial state value.
    ///   - environment: The environment values for dependency injection. Defaults to the shared instance.
    public init(state: State, environment: AsyncStoreEnvironmentValues = .shared) {
        self.state = state
        self.env = environment
        
        let runStream = AsyncStream<Effect> { continuation in
            self.runContinuation = continuation
        }
        
        runTask = Task { [weak self] in
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
    /// Dispatches an effect to the store for processing.
    ///
    /// This is the primary entry point for all state changes. Effects are processed
    /// asynchronously in the order they are dispatched.
    ///
    /// - Parameter effect: The effect to execute.
    func run(_ effect: Effect) {
        runContinuation?.yield(effect)
    }
    
    /// Creates a two-way SwiftUI `Binding` for a state property.
    ///
    /// The binding reads the current value from state and writes new values back,
    /// propagating changes to any active state streams.
    ///
    /// - Parameter property: A writable key path to the state property.
    /// - Returns: A `Binding` that reads from and writes to the store's state.
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
    
    /// Binds this store to a property of a shared repository store.
    ///
    /// When the observed property changes in the repository, the `map` closure converts
    /// the new value into an effect that is dispatched on this store. Duplicate values
    /// are automatically filtered.
    ///
    /// - Parameters:
    ///   - repoKey: The repository key type identifying the shared store.
    ///   - keyPath: A key path to the property to observe on the shared store's state.
    ///   - map: A closure that converts the new property value into an effect for this store.
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
    
    /// Reads the current value of a property from a shared repository store.
    ///
    /// - Parameters:
    ///   - key: The repository key type identifying the shared store.
    ///   - keyPath: A key path to the property to read.
    /// - Returns: The current value of the property.
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
        setter(&state)
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
