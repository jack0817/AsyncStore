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

actor StoreWaiter<State, Environment> {
    let store: AsyncStore<State, Environment>
    
    init(store: AsyncStore<State, Environment>) {
        self.store = store
    }
    
    func waitForObjectWillChange(
        count: Int,
        timeout: TimeInterval
    ) async {
        var currentCount = 0
        var cancellable: AnyCancellable? = .none
        
        let timeoutTask = Task {
            guard !Task.isCancelled else { return }
            try? await Task.trySleep(for: timeout)
        }
        
        cancellable = store.objectWillChange
            .sink { _ in
                guard !timeoutTask.isCancelled else { return }
                currentCount += 1
                if currentCount == count {
                    timeoutTask.cancel()
                }
            }
        
        await timeoutTask.value
        cancellable?.cancel()
        
        switch currentCount {
        case count:
            break
        default:
            XCTFail("Store (\(type(of: store)) timed out after \(timeout) seconds. Count:\(currentCount)")
        }
    }
}
