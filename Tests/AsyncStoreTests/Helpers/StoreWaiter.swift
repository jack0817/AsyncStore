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

final class StoreWaiter<State: Equatable, Env> {
    let count: Int
    private var cancellable: AnyCancellable! = .none
    private var counterTask: Task<Int, Never>! = .none
    private var waitTask: Task<Bool, Never>! = .none
    
    init(store: AsyncStore<State, Env>, count: Int) {
        self.count = count
        
        let stream = store.stream(
            for: "\(type(of: store)).StoreWaiter",
            at: \.self,
            bufferingPolicy: .unbounded
        )
        .dropFirst()
        
        counterTask = Task {
            var streamCount = 0
            do {
                for try await _ in stream {
                    guard !Task.isCancelled else { break }
                    streamCount += 1
                    if streamCount >= count {
                        waitTask?.cancel()
                    }
                }
            } catch {
                print("\(error)")
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
            defer { counterTask?.cancel() }
            do {
                try await Task.trySleep(for: timeout)
                return true
            } catch {
                return false
            }
        }
    
        let actualCount = await counterTask.value
        let didTimeOut = await waitTask.value
        
        switch didTimeOut {
        case true:
            XCTFail("Store timed out after \(timeout) seconds. Actual:\(actualCount) Expected:\(count)")
        case _ where actualCount != count:
            XCTFail("Incorrect count. Actual:\(actualCount) Expected:\(count)")
        default:
            return
        }
    }
}

