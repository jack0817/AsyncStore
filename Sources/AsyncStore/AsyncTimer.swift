//
//  File.swift
//  
//
//  Created by Wendell Thompson on 4/6/22.
//

import Foundation

extension AsyncStore {
    struct AsyncTimer: AsyncSequence {
        typealias Element = Date
        typealias AsyncIterator = AsyncStore.AsyncTimer.Iterator
        
        let interval: TimeInterval
        
        func makeAsyncIterator() -> Iterator {
            AsyncTimer.Iterator(interval: interval)
        }
    }
}

extension AsyncStore.AsyncTimer {
    struct Iterator: AsyncIteratorProtocol {
        let interval: TimeInterval
        private var offsetTime: UInt64 = 0
        
        private var nowNano: UInt64 {
            DispatchTime.now().uptimeNanoseconds
        }
        
        init(interval: TimeInterval) {
            self.interval = interval
        }
        
        mutating func next() async -> Element? {
            do {
                let start = nowNano
                let sleep = UInt64(interval * 1_000_000_000) - offsetTime
                try await Task.sleep(nanoseconds: sleep)
                let elapsed = nowNano - start
                offsetTime = elapsed > sleep ? elapsed - sleep : 0
                return .now
            } catch {
                return .none
            }
        }
    }
}
