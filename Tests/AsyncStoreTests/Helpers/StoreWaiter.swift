//
//  StoreWaiter.swift
//
//
//  Created by Wendell Thompson (AO) on 2/15/22.
//

import Foundation
import Combine
import XCTest
@testable import AsyncStore
import SwiftUI

final class StoreWaiter<State, Env> {
    let count: Int
    private var cancellable: AnyCancellable! = .none
    private var counterTask: Task<Int, Never>! = .none
    private var waitTask: Task<Void, Never>? = .none
    
    init(store: AsyncStore<State, Env>, count: Int) {
        self.count = count
        
        let stream = AsyncStream<Void> { cont in
            cancellable = store.objectWillChange
                .sink { _ in
                    cont.yield(())
                }
        }
        
        counterTask = Task {
            var streamCount = 0
            for await _ in stream {
                guard !Task.isCancelled else { break }
                streamCount += 1
                if streamCount >= count {
                    waitTask?.cancel()
                }
            }
            return streamCount
        }
    }
    
    deinit {
        cancellable?.cancel()
        counterTask?.cancel()
        waitTask?.cancel()
    }
    
    func wait(timeout: TimeInterval) async {
        waitTask = Task {
            try? await Task.trySleep(for: timeout)
            counterTask?.cancel()
        }
    
        let actualCount = await counterTask.value
        if actualCount != count {
            XCTFail("Store timed out after \(timeout) seconds. Count:\(actualCount)")
        }
    }
}

