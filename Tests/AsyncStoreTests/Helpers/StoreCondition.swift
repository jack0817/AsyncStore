//
//  File.swift
//  
//
//  Created by Wendell Thompson on 11/4/22.
//

import Foundation
import Atomics
import XCTest
@testable import AsyncStore

final class StoreCondition<State: Equatable, Environment> {
    enum WaitState: UInt8, AtomicValue {
        case waiting
        case completed
        case timedOut
    }
    
    private let store: AsyncStore<State, Environment>
    private let condition: (State) -> Bool
    private let waitState = ManagedAtomic<WaitState>(.waiting)
    private var waitTask: Task<Void, Never>? = .none
    private var timeoutTask: Task<Void, Never>? = .none
    
    init(store: AsyncStore<State, Environment>, condition: @escaping (State) -> Bool) {
        self.store = store
        self.condition = condition
    }
    
    func wait(for timeout: TimeInterval) async {
        guard !condition(store.state) else { return }
        
        let stream = store.stream(for: "\(type(of: self)).waiter", at: \.self)
        waitTask = Task {
            do {
                for try await state in stream {
                    guard condition(state) else { continue }
                    setWaitState(to: .completed)
                }
            } catch {
                print("\(error)")
            }
        }
        
        timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeout.nanoSeconds)
                setWaitState(to: .timedOut)
            } catch { }
        }
        
        await waitTask?.value
        await timeoutTask?.value
        
        switch waitState.load(ordering: .sequentiallyConsistent) {
        case .timedOut:
            XCTFail("Store timed out after \(timeout) seconds.")
        default:
            return
        }
    }
    
    private func setWaitState(to newState: WaitState) {
        let currentState = waitState.load(ordering: .sequentiallyConsistent)
        guard currentState == .waiting else { return }
        
        var exchanged = false
        while !exchanged {
            exchanged = waitState.compareExchange(
                expected: .waiting,
                desired: newState,
                ordering: .sequentiallyConsistent
            ).exchanged
        }
        
        waitTask?.cancel()
        timeoutTask?.cancel()
    }
}
