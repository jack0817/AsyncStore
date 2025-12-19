//
//  AsyncStoreEffect.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/16/25.
//

import Foundation

public extension AsyncStore {
    enum Effect: Sendable {
        case none
        case set(@Sendable (inout State) -> Void)
        case task(AsyncTask, id: TaskIdentifier?)
        case concatenate([Effect])
        case merge([Effect])
    }
}

// MARK: Effect Extensions

public extension AsyncStore.Effect {
    static func set<Value: Sendable>(
        _ keyPath: WritableKeyPath<State, Value>,
        to value: Value
    ) -> Self {
        .set { $0[keyPath: keyPath] = value }
    }
    
    static func task(
        _ operation : @Sendable @escaping () async throws -> Self
    ) -> Self {
        .task(operation, id: .none)
    }
    
    static func task<P: Sendable>(
        _ operation : @Sendable @escaping (P) async throws -> Self,
        _ param: P,
        id: TaskIdentifier? = .none
    ) -> Self {
        .task({ try await operation(param) }, id: id)
    }
    
    static func concatenate(_ effects: Self ...) -> Self {
        .concatenate(effects)
    }
    
    static func merge(_ effects: Self ...) -> Self {
        .merge(effects)
    }
}


// TODO: Determine if this is needed
extension KeyPath: @unchecked @retroactive Sendable {}
