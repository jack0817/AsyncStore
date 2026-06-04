//
//  StoreWaiter.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

@testable import AsyncStore
import Foundation
import Testing

@MainActor
public final class StoreWaiter<State: Sendable, TaskId: Hashable & Sendable> {
    public typealias Store = AsyncStore<State, TaskId>
    let store: Store
    
    public init(store: Store) {
        self.store = store
    }
    
    @discardableResult
    func wait<Value: Equatable & Sendable>(
        for property: KeyPath<State, Value>,
        count: Int = 1,
        running effect: Store.Effect,
        timeout: TimeInterval = 4.0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Self {
        try await wait(
            for: property,
            count: count,
            running: { $0.run(effect) },
            timeout: timeout,
            sourceLocation: sourceLocation)
    }
    
    @discardableResult
    func wait<Value: Equatable & Sendable>(
        for property: KeyPath<State, Value>,
        count: Int = 1,
        running operation: (Store) -> Void,
        timeout: TimeInterval = 4.0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Self {
        var updateTask: Task<Int, Never>? = .none
        
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return false  }
                updateTask?.cancel()
                return true
            } catch {
                return false
            }
        }
        
        updateTask = Task {
            let updateStream = store.stream(for: property).dropFirst()
            var updateCount = 0
            
            for await _ in updateStream {
                guard !Task.isCancelled else { return updateCount }
                updateCount += 1
                if updateCount >= count { break }
            }
            
            timeoutTask.cancel()
            return updateCount
        }
        
        operation(store)
        
        let didTimeout = await timeoutTask.value
        let updateCount = await updateTask?.value ?? 0
        try #require(!didTimeout, "Timed out after \(timeout) seconds", sourceLocation: sourceLocation)
        try #require(updateCount == count, sourceLocation: sourceLocation)
        
        return self
    }
    
    @discardableResult
    func expect<Value: Equatable>(
        _ property: KeyPath<State, Value>,
        toEqual value: Value,
        comment: Comment? = .none,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Self {
        expect(
            { $0[keyPath: property] == value },
            comment: comment ?? "Store property '\(property)' did not equal \(value)",
            sourceLocation: sourceLocation
        )
    }
    
    @discardableResult
    func expect(
        _ condition: (State) -> Bool,
        comment: Comment? = .none,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Self {
        #expect(
            condition(store.state),
            comment,
            sourceLocation: sourceLocation
        )
        
        return self
    }
    
    @discardableResult
    func require<Value: Equatable>(
        _ property: KeyPath<State, Value>,
        toEqual value: Value,
        comment: Comment? = .none,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Self {
        try require(
            { $0[keyPath: property] == value },
            comment: comment,
            sourceLocation: sourceLocation
        )
    }
    
    @discardableResult
    func require(
        _ condition: (State) -> Bool,
        comment: Comment? = .none,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Self {
        try #require(condition(store.state), comment, sourceLocation: sourceLocation)
        return self
    }
}
