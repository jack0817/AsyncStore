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
    static func set<Value: Sendable>(_ property: WritableKeyPath<State, Value>, to value: Value) -> Self {
        .set { $0[keyPath: property] = value }
    }
    
    static func task(_ operation: @Sendable @escaping () async throws -> Self) -> Self {
        .task(operation, id: .none)
    }
    
    static func task<Parameter: Sendable>(
        id: TaskIdentifier? = .none,
        param: Parameter,
        _ operation: @Sendable @escaping (Parameter) async throws -> Self
    ) -> Self {
        .task({ try await operation(param) }, id: id)
    }
    
    static func concatenate(_ effects: Self ...) -> Self {
        self.concatenate(effects)
    }
    
    static func merge(_ effects: Self ...) -> Self {
        self.merge(effects)
    }
}

public extension AsyncStore.Effect {
    static func append<Element: Sendable>(
        _ element: Element,
        to property: WritableKeyPath<State, Array<Element>>
    ) -> Self {
        .set { $0[keyPath: property].append(element) }
    }
    
    static func append<Element: Sendable>(
        contentsOf array: Array<Element>,
        to property: WritableKeyPath<State, Array<Element>>
    ) -> Self {
        .set { $0[keyPath: property].append(contentsOf: array) }
    }
}
