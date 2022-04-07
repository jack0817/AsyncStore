//
//  File.swift
//  
//
//  Created by Wendell Thompson on 4/6/22.
//

import Foundation

extension AsyncStore {
    struct AsyncTimer: AsyncSequence {
        typealias AsyncIterator = AsyncStore.AsyncTimer.Iterator
        typealias Element = Date
        
        let interval: TimeInterval
        
        func makeAsyncIterator() -> AsyncStore<State, Environment>.AsyncTimer.Iterator {
            .init(interval: interval)
        }
    }
}

extension AsyncStore.AsyncTimer {
    struct Iterator: AsyncIteratorProtocol {
        let interval: TimeInterval
        
        mutating func next() async throws -> Date? {
            try? await Task.trySleep(for: interval)
            guard !Task.isCancelled else { return .none }
            return Date()
        }
    }
}
