//
//  Effect.swift
//  
//
//  Created by Wendell Thompson (AO) on 2/14/22.
//

import Foundation

public extension AsyncStore {
    enum Effect {
        case none
        case set((inout State) -> Void)
        case task(operation: () async throws -> Effect, id: AnyHashable?)
        case sleep(TimeInterval)
        case timer(TimeInterval, id: AnyHashable, mapEffect: (Date) -> Effect)
        case cancel(AnyHashable)
        case merge(effects: [Effect])
        case concatenate(effects: [Effect])
    }
}

public extension AsyncStore.Effect {
    static func set<Value>(_ keyPath: WritableKeyPath<State, Value>, to value: Value) -> Self {
        return .set { $0[keyPath: keyPath] = value }
    }
    
    static func task(
        _ operation: @escaping () async throws -> Self,
        _ id: AnyHashable? = .none
    ) -> Self {
        .task(operation: operation, id: id)
    }
    
    static func dataTask<Data>(
        _ data: Data,
        _ operation: @escaping (Data) async throws -> Self,
        _ id: AnyHashable? = .none
    ) -> Self {
        .task(operation: { try await operation(data) }, id: id)
    }
    
    static func debounce(
        task operation: @escaping () async throws -> Self,
        id: AnyHashable,
        delay: TimeInterval
    ) -> Self {
        .task(
            operation: {
                try await Task.trySleep(for: delay)
                return try await operation()
            },
            id: id
        )
    }
    
    static func debounce<Data>(
        data: Data,
        task operation: @escaping (Data) async throws -> Self,
        id: AnyHashable,
        delay: TimeInterval
    ) -> Self {
        .debounce(
            task: { try await operation(data) },
            id: id,
            delay: delay
        )
    }
    
    static func merge(_ effects: Self ...) -> Self {
        .merge(effects: effects)
    }
    
    static func concatenate(_ effects: Self ...) -> Self {
        .concatenate(effects: effects)
    }
}

// MARK: Sequences

public extension AsyncStore.Effect {
    static func append<Element>(_ element: Element, to sequence: WritableKeyPath<State, [Element]>) -> Self {
        .set { state in state[keyPath: sequence].append(element) }
    }
    
    static func insert<Element>(_ element: Element, at index: Int, to sequence: WritableKeyPath<State, [Element]>) -> Self {
        .set { state in state[keyPath: sequence].insert(element, at: index) }
    }
    
    static func remove<Element>(at index: Int, from sequence: WritableKeyPath<State, [Element]>) -> Self {
        .set { state in state[keyPath: sequence].remove(at: index) }
    }
    
    static func removeFirst<Element>(from sequence: WritableKeyPath<State, [Element]>) -> Self {
        .set { state in state[keyPath: sequence].removeFirst() }
    }
    
    static func removeLast<Element>(from sequence: WritableKeyPath<State, [Element]>) -> Self {
        .set { state in state[keyPath: sequence].removeLast() }
    }
}
