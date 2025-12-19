//
//  AsyncStore.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/15/25.
//

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
    private var runEffectTask: Task<Void, Never>? = .none
    
    @ObservationIgnored
    private var runContinuation: AsyncStream<Effect>.Continuation? = .none
    
    @ObservationIgnored
    private var tasks: [TaskIdentifier: Task<Void, Never>] = [:]

    public init(state: State) {
        self.state = state
        
        let stream = AsyncStream<Effect> { continuation in
            self.runContinuation = continuation
        }
        
        self.runEffectTask = Task(priority: .background) { [weak self] in
            for await effect in stream {
                guard let self, !Task.isCancelled else { return }
                await self.reduce(effect)
            }
        }
    }
    
    deinit {
        runContinuation?.finish()
        runEffectTask?.cancel()
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
        runContinuation?.yield(effect)
    }
    
    func store<Key: AsyncStoreEnvironmentKey>(for key: Key.Type) -> Key.Store {
        AsyncStoreEnvironmentValues.shared[key]
    }
}

// MARK: Private API

fileprivate extension AsyncStore {
    nonisolated
    func reduce(_ effect: Effect, awaitTask: Bool = false) async {
        switch effect {
        case .none:
            break
        case .set(let setter):
            await execute(setter)
        case .task(let operation, let id):
            print("[AsyncStore] executing \(String(describing: id))")
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
            await withTaskGroup { [weak self] group in
                for effect in effects {
                    guard let self else { break }
                    group.addTask { await self.reduce(effect) }
                }
                
                for await _ in group { }
            }
        }
    }
}

// MARK: Private API

fileprivate extension AsyncStore {
    func track(_ task: Task<Void, Never>, for id: TaskIdentifier?) {
        guard let id else { return }
        tasks[id] = task
    }

    func execute(_ setter: (inout State) -> Void) {
        setter(&state)
    }
    
    func perform(_ operation: @escaping AsyncTask) async -> Effect {
        do {
            return try await operation()
        } catch {
            return .none
        }
    }
}
