//
//  AsyncStoreEffect.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import Foundation

public extension AsyncStore {
    /// A declarative description of a state change or async operation to be performed by the store.
    ///
    /// Effects are the sole mechanism for mutating store state. They range from simple synchronous
    /// mutations to complex compositions of async work.
    enum Effect: Sendable {
        /// A no-op effect that leaves state unchanged.
        case none
        /// A synchronous state mutation described by a closure.
        case set(@Sendable (inout State) -> Void)
        /// An asynchronous operation that returns a new effect when complete. The optional `id`
        /// parameter allows the store to cancel a previous task with the same identifier.
        case task(@Sendable () async throws -> Effect, id: TaskIdentifier?)
        /// A sequence of effects executed one after another. Each effect completes before the next begins.
        case concatenate([Effect])
        /// A set of effects executed concurrently. All effects start immediately and complete independently.
        case merge([Effect])
    }
}

public extension AsyncStore.Effect {
    /// Sets a single state property to a given value.
    ///
    /// - Parameters:
    ///   - property: A writable key path to the property.
    ///   - value: The new value to assign.
    static func set<Value: Sendable>(
        _ property: WritableKeyPath<State, Value>,
        to value: Value
    ) -> Self {
        .set { $0[keyPath: property] = value }
    }
    
    /// Creates a task effect without a cancellation identifier.
    ///
    /// - Parameter operation: The async operation to perform.
    static func task(_ operation: @Sendable @escaping () async throws -> Self) -> Self {
        .task(operation, id: .none)
    }
    
    /// Creates a task effect that captures a `Sendable` parameter.
    ///
    /// - Parameters:
    ///   - param: The parameter to pass into the operation.
    ///   - id: An optional task identifier for cancellation.
    ///   - operation: The async operation receiving the parameter.
    static func task<Param: Sendable>(
        param: Param,
        id: TaskIdentifier? = .none,
        _ operation: @Sendable @escaping (Param) async throws -> Self
    ) -> Self {
        .task({ try await operation(param) }, id: id)
    }
    
    /// Creates a concatenation of effects from a variadic list.
    static func concatenate(_ effects: Self ...) -> Self {
        .concatenate(effects)
    }
    
    /// Creates a merge of effects from a variadic list.
    static func merge(_ effects: Self ...) -> Self {
        .merge(effects)
    }
}

public extension AsyncStore.Effect {
    /// Appends an element to an array property on the state.
    ///
    /// - Parameters:
    ///   - element: The element to append.
    ///   - array: A writable key path to the array property.
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
