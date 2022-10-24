//
//  File.swift
//  
//
//  Created by Wendell Thompson on 10/23/22.
//

import Foundation
import Atomics

final class AsyncAtomicStore<Value> {
    enum Action: UInt8, AtomicValue {
        case ready
        case setting
        case getting
        case counting
    }
    
    private let currentAction = ManagedAtomic<AsyncAtomicStore.Action>(.ready)
    private var store: [AnyHashable: Value] = [:]
    
    subscript (id: AnyHashable) -> Value? {
        get { perform(.getting, operation: { store[id] }) }
        set { perform(.setting, operation: { store[id] = newValue }) }
    }
    
    public func count() -> Int {
        perform(.counting, operation: { store.count })
    }
    
    public func keys() -> [AnyHashable] {
        perform(.getting, operation: { Array(store.keys) })
    }
    
    public func set(id: AnyHashable, to value: Value?) {
        perform(.setting, operation: { store[id] = value })
    }
    
    public func get(id: AnyHashable) -> Value? {
        perform(.getting, operation: { store[id] })
    }
    
    public func clear() {
        perform(.setting, operation: { store = [:] })
    }
}

// MARK: Atomic Operations

fileprivate extension AsyncAtomicStore {
    func perform<Value>(_ action: AsyncAtomicStore.Action, operation: () -> Value) -> Value {
        var exchanged = false
        while !exchanged {
            exchanged = currentAction.compareExchange(
                expected: .ready,
                desired: action,
                ordering: .sequentiallyConsistent
            ).exchanged
        }

        let value = operation()

        var isReady = false
        while !isReady {
            isReady = currentAction.compareExchange(
                expected: action,
                desired: .ready,
                ordering: .sequentiallyConsistent
            ).exchanged
        }
        
        return value
    }
}
