//
//  StoreWaiter.swift
//
//
//  Created by Wendell Thompson (AO) on 2/15/22.
//

import Foundation
import XCTest
import SwiftUI
import Atomics
@testable import AsyncStore

final class StoreWaiter<State: Equatable, Env> {
    enum State: UInt8, AtomicValue {
        case ready
        case timedOut
        case completed
    }
    
    enum Error: Swift.Error {
        case failedToChangeState(from: StoreWaiter.State, to: StoreWaiter.State, current: StoreWaiter.State)
    }
    
    let state = ManagedAtomic<StoreWaiter.State>(.ready)
    let count: Int
    private var counterTask: Task<Int, Never>! = .none
    private var waitTask: Task<Void, Never>! = .none
    
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
                    guard state.load(ordering: .sequentiallyConsistent) == .ready else { break }
                    streamCount += 1
                    if streamCount == count {
                        waitTask?.cancel()
                        try setState(from: .ready, to: .completed)
                    }
                }
            } catch {
                print("\(error)")
            }
            
            return streamCount
        }
    }
    
    deinit {
        counterTask?.cancel()
        waitTask?.cancel()
    }
    
    func wait(timeout: TimeInterval) async {
        waitTask = Task {
            defer { counterTask?.cancel() }
            do {
                try await Task.trySleep(for: timeout)
                try setState(from: .ready, to: .timedOut)
            } catch {
                print(error)
            }
        }
    
        let actualCount = await counterTask.value
        await waitTask.value
        let currentState = state.load(ordering: .sequentiallyConsistent)
        
        switch currentState {
        case .timedOut:
            XCTFail("Store timed out after \(timeout) seconds. Actual:\(actualCount) Expected:\(count)")
        case .completed where actualCount != count:
            XCTFail("Incorrect count. Actual:\(actualCount) Expected:\(count)")
        default:
            return
        }
    }
    
    private func setState(from fromState: StoreWaiter.State, to toState: StoreWaiter.State) throws {
        let exchange = state.compareExchange(
            expected: fromState,
            desired: toState,
            ordering: .sequentiallyConsistent
        )
        
        if !exchange.exchanged {
            let currentState = state.load(ordering: .sequentiallyConsistent)
            throw StoreWaiter.Error.failedToChangeState(
                from: fromState,
                to: toState,
                current: currentState
            )
        }
    }
}

