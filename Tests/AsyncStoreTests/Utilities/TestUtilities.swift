//
//  TestUtilities.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/20/25.
//

import AsyncStore
import Foundation
import Testing

enum WaitError: Swift.Error {
    case timedout
}

public extension AsyncStore {
    func wait<Value>(
        for property: KeyPath<State, Value>,
        updateCount count: Int = 1,
        running effect: Effect,
        timeout: TimeInterval = 4.0,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws where Value: Equatable & Sendable {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Swift.Error>) in
            var didTimeout = false
            
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(timeout))
                didTimeout = true
                continuation.resume(throwing: WaitError.timedout)
            }
            
            Task { @MainActor in
                var counter = 0
                let stream = stream(for: property)

                for await _ in stream {
                    counter += 1
                    guard counter < count else {
                        timeoutTask.cancel()
                        if !didTimeout { continuation.resume() }
                        break
                    }
                }
            }
            
            run(effect)
        }
    }
}
