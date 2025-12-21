//
//  File.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/20/25.
//

import AsyncStore
import Foundation
import Testing

@MainActor
final class StoreAwaiter<State: Sendable, TaskId: Hashable & Sendable> {
    enum Error: Swift.Error {
        case timedout
    }
    
    let store: AsyncStore<State, TaskId>
    
    init(store: AsyncStore<State, TaskId>) {
        self.store = store
    }
    
    func wait<Value: Equatable & Sendable>(
        for property: KeyPath<State, Value>,
        count: Int = 1,
        running effect: AsyncStore<State, TaskId>.Effect,
        timeout: TimeInterval = 4.0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Swift.Error>) in
            var didTimeout = false
            
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(timeout))
                didTimeout = true
                continuation.resume(throwing: Error.timedout)
            }
            
            Task { @MainActor in
                var counter = 0
                let stream = store.stream(for: property)

                for await _ in stream {
                    counter += 1
                    print("[\(type(of: self))] counter: \(counter) count: \(count)")
                    guard counter < count else {
                        timeoutTask.cancel()
                        if !didTimeout { continuation.resume() }
                        break
                    }
                }
            }
            
            store.run(effect)
        }
    }
}
