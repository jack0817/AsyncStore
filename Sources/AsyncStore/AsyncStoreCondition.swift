//
//  AsyncStoreCondition.swift
//  
//
//  Created by Wendell Thompson on 11/18/22.
//

import Foundation
import Atomics

public final class AsyncStoreCondition<State, Environment> {
    public enum WaitState: UInt8, AtomicValue {
        case waiting
        case completed
        case timedOut
    }

    private let store: AsyncStore<State, Environment>
    private let waitState = ManagedAtomic<WaitState>(.waiting)
    private var conditionTask: Task<Void, Never>? = .none
    private var timeoutTask: Task<Void, Never>? = .none
    
    init(_ store: AsyncStore<State, Environment>) {
        self.store = store
    }
    
    @discardableResult
    public func wait<Value: Equatable>(
        for property: KeyPath<State, Value>,
        toEqual value: Value,
        timeout: TimeInterval
    ) async -> WaitState {
        await wait(for: property, toEqual: { $0 == value }, timeout: timeout)
    }
    
    @discardableResult
    public func wait<Value: Equatable>(
        for property: KeyPath<State, Value>,
        toEqual condition: @escaping (Value) -> Bool,
        timeout: TimeInterval
    ) async -> WaitState {
        let stream = store.stream(for: "\(type(of: self)).\(self)", at: property)
        conditionTask = Task {
            do {
                for try await value in stream {
                    if condition(value) {
                        setWaitState(to: .completed)
                    }
                }
            } catch {}
        }
        
        timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeout.nanoSeconds)
                setWaitState(to: .timedOut)
            } catch { }
        }
        
        await conditionTask?.value
        await timeoutTask?.value
        return waitState.load(ordering: .sequentiallyConsistent)
    }
    
    private func setWaitState(to newState: WaitState) {
        let currentWaitState = waitState.load(ordering: .sequentiallyConsistent)
        guard currentWaitState == .waiting else { return }
        
        var isExchanged = false
        while (!isExchanged) {
            isExchanged = waitState.compareExchange(
                expected: .waiting,
                desired: newState,
                ordering: .sequentiallyConsistent
            ).exchanged
        }
        
        conditionTask?.cancel()
        timeoutTask?.cancel()
    }
}
