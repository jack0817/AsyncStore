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
    
    @MainActor
    public init(state: State) {
        self.state = state
        
        let runStream = AsyncStream<Effect> { continuation in
            self.runContinuation = continuation
        }
        
        runTask = Task(priority: .background) { @MainActor in
            for await effect in runStream {
                guard !Task.isCancelled else { break }
                await reduce(effect)
            }
        }
    }
    
    deinit {
        runContinuation?.finish()
        runTask?.cancel()
        tasks.values.forEach { $0.cancel() }
        stateContinuations.values.forEach { $0.finish() }
    }
    
    public subscript<Value>(dynamicMember property: KeyPath<State, Value>) -> Value {
        get { state[keyPath: property] }
    }
    
    public func run(_ effect: Effect) {
        runContinuation?.yield(effect)
    }
    
    public func stream<Value: Equatable & Sendable>(
        for keyPath: KeyPath<State, Value>
    ) -> AnyAsyncSequence<Value> {
        let stateStream = AsyncStream<State> { continuation in
            stateContinuations[.init()] = continuation
        }
        
        return stateStream
            .map { $0[keyPath: keyPath] }
            .removeDuplicates()
            .eraseToAnyAsyncSequence()
    }
}

fileprivate extension AsyncStore {
    @MainActor
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
