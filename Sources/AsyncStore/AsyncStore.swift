//
//  AsyncStore.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/15/25.
//

import AsyncAlgorithms
import Foundation
import SwiftUI

// MARK: Store

@MainActor
@Observable
@dynamicMemberLookup
public final class AsyncStore<State: Sendable, TaskIdentifier: Hashable & Sendable> {
    public typealias AsyncTask = @Sendable () async throws -> Effect
    
    fileprivate(set) var state: State
    
    @ObservationIgnored
    public var mapError: (Error) -> Effect = { _ in .none }
    
    @ObservationIgnored
    private var tasks: [TaskIdentifier: Task<Void, Never>] = [:]
    
    @ObservationIgnored
    private var stateContinuations: [Int: AsyncStream<State>.Continuation] = [:]
    
    @ObservationIgnored
    private let logger = AsyncStoreLogger(.info)

    public init(state: State) {
        self.state = state
        logger.info("[\(type(of: self))] init")
    }
    
    deinit {
        stateContinuations.values.forEach { $0.finish() }
        logger.info("[\(type(of: self))] deint")
    }

    public subscript <Value>(dynamicMember dynamicMember: KeyPath<State, Value>) -> Value {
        get { state[keyPath: dynamicMember] }
    }
}

// MARK: Public API

public extension AsyncStore {
    func cancel(id: TaskIdentifier) {
        tasks[id]?.cancel()
    }

    func binding<Value: Equatable & Sendable>(
        on keyPath: WritableKeyPath<State, Value>
    ) -> Binding<Value> {
        binding(on: keyPath, effect: { .set(keyPath, to: $0) })
    }
    
    func binding<Value: Equatable & Sendable>(
        on keyPath: WritableKeyPath<State, Value>,
        effect: @escaping (Value) -> Effect
    ) -> Binding<Value> {
        let defaultValue = state[keyPath: keyPath]
        
        return .init(
            get: { [weak self] in self?.state[keyPath: keyPath] ?? defaultValue },
            set: { [weak self] in self?.run(effect($0)) }
        )
    }
    
    func run(_ effect: Effect) {
        Task { await reduce(effect) }
    }
    
    func store<Key: AsyncStoreEnvironmentKey>(for key: Key.Type) -> Key.Store {
        AsyncStoreEnvironmentValues.shared[key]
    }
    
    func stream<Value: Equatable & Sendable>(
        for property: KeyPath<State, Value>
    ) -> AnyAsyncSequence<Value> {
        AsyncStream<State> { continuation in
            if stateContinuations[continuation.hashValue] != .none {
                logger.warning(
                    """
                    [\(type(of: self))] Existing continuation for \(property) is being overwritten
                    """
                )
            }

            stateContinuations[continuation.hashValue] = continuation
            continuation.yield(state)
        }
        .map { $0[keyPath: property] }
        .removeDuplicates()
        .dropFirst()
        .eraseToAnyAsyncSequence()
    }
    
    func finishAllStreams() {
        stateContinuations.values.forEach { $0.finish() }
        stateContinuations = [:]
    }
}

// MARK: Private API

fileprivate extension AsyncStore {
    final class Flag {
        var value: Bool = false
        
        func toggle() {
            self.value = !value
        }
    }
    
    nonisolated
    func reduce(_ effect: Effect, awaitTask: Bool = false) async {
        switch effect {
        case .none:
            break
        case .set(let setter):
            await execute(setter)
        case .task(let operation, let id):
            let task = Task {
                let effect = await perform(operation)
                await run(effect)
            }
            
            await track(task, for: id)
            
            guard awaitTask else { return }
            await task.value
        case .concatenate(let effects):
            for effect in effects {
                await reduce(effect, awaitTask: true)
            }
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
        }
    }
}

// MARK: Private API

fileprivate extension AsyncStore {
    func track(_ task: Task<Void, Never>, for id: TaskIdentifier?) {
        guard let id else { return }
        if let existingTask = tasks[id] {
            logger.warning("[\(type(of: self))] cancelling existing task for \(id)")
            existingTask.cancel()
        }
        
        tasks[id] = task
    }

    func execute(_ setter: (inout State) -> Void) {
        setter(&state)
        yieldState()
    }
    
    func yieldState() {
        var terminatedKeys: [Int] = []
        
        stateContinuations.values.forEach { continuation in
            switch continuation.yield(state) {
            case .terminated:
                terminatedKeys.append(continuation.hashValue)
                logger.warning("[\(type(of: self))] yield to terminated continuation")
            default:
                break
            }
        }
        
        terminatedKeys.forEach {
            stateContinuations[$0]?.finish()
            stateContinuations[$0] = .none
        }
    }
    
    func perform(_ operation: @escaping AsyncTask) async -> Effect {
        do {
            return try await operation()
        } catch {
            logger.info("[\(type(of: self))] mapping error '\(error.localizedDescription)'")
            return mapError(error)
        }
    }
}

