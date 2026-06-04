//
//  AsyncStoreEffect.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import Foundation

public extension AsyncStore {
    enum Effect: Sendable {
        case none
        case set(@Sendable (inout State) -> Void)
        case task(@Sendable () async throws -> Effect, id: TaskIdentifier?)
        case concatenate([Effect])
        case merge([Effect])
    }
}

public extension AsyncStore.Effect {
    static func set<Value: Sendable>(
        _ property: WritableKeyPath<State, Value>,
        to value: Value
    ) -> Self {
        .set { $0[keyPath: property] = value }
    }
    
    static func task(_ operation: @Sendable @escaping () async throws -> Self) -> Self {
        .task(operation, id: .none)
    }
    
    static func task<Param: Sendable>(
        param: Param,
        id: TaskIdentifier? = .none,
        _ operation: @Sendable @escaping (Param) async throws -> Self
    ) -> Self {
        .task({ try await operation(param) }, id: id)
    }
}

public extension AsyncStore.Effect {
    static func append<Element: Sendable>(
        _ element: Element,
        to array: WritableKeyPath<State, Array<Element>>
    ) -> Self {
        .set { $0[keyPath: array].append(element) }
    }
}

// MARK: Extensions

extension KeyPath: @retroactive @unchecked Sendable where Value: Sendable { }
extension WritableKeyPath: @retroactive @unchecked Sendable where Value: Sendable { }
