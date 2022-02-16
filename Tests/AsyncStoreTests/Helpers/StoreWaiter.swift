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
    private var currentCount = 0
    private var cancellable: AnyCancellable! = .none
    private var counterTask: Task<Void, Never>! = .none
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
            for await _ in stream {
                currentCount += 1
                if currentCount >= count {
                    waitTask?.cancel()
                }
            }
        }
    }
    
    deinit {
        cancellable?.cancel()
        counterTask?.cancel()
        waitTask?.cancel()
    }
    
    func wait(timeout: TimeInterval) async {
        guard currentCount < count else { return }
        waitTask = Task {
            try? await Task.trySleep(for: timeout)
        }
        
        await waitTask?.value
        if currentCount < count {
            XCTFail("Store timed out after \(timeout) seconds. Count:\(currentCount)")
        }
    }
}

