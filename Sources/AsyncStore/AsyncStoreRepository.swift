//
//  AsyncStoreRepository.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import Foundation
import SwiftUI

/// A protocol for defining keys used to register and look up shared stores in the repository.
///
/// Conform to this protocol with an enum to declare the state and task identifier types
/// of the shared store.
public protocol AsyncStoreRepositoryKey {
    /// The state type of the shared store.
    associatedtype State: Sendable
    /// The task identifier type of the shared store.
    associatedtype TaskIdentifier: Sendable & Hashable
    /// A convenience alias for the full store type.
    typealias Store = AsyncStore<State, TaskIdentifier>
}

/// A singleton registry for shared stores that enables cross-feature state sharing.
///
/// Register stores at app launch and access them from any feature store using
/// ``AsyncStore/repo(for:_:)`` for one-time reads or ``AsyncStore/bind(_:to:map:)``
/// for reactive bindings.
public final class AsyncStoreRepository {
    /// The shared repository instance.
    @MainActor
    public static let shared = AsyncStoreRepository()
    
    private var storage: [ObjectIdentifier: Any] = [:]
    
    private init() { }
    
    public subscript<Key: AsyncStoreRepositoryKey>(_ key: Key.Type) -> Key.Store {
        get {
            let id = ObjectIdentifier(key)
            guard let store = storage[id] as? Key.Store else {
                fatalError("No store found for key \(key)")
            }
            return store
        } set {
            let id = ObjectIdentifier(key)
            storage[id] = newValue
        }
    }
}

// MARK: Property Wrapper

@propertyWrapper
public final class AsyncStoreRepoProperty<
    Key: AsyncStoreRepositoryKey,
    Value: Equatable & Sendable
>: @MainActor DynamicProperty {
    @State private var value: Value
    private let property: KeyPath<Key.State, Value>
    
    @MainActor
    init(_ key: Key.Type, _ property: KeyPath<Key.State, Value>) {
        self.value = AsyncStoreRepository.shared[Key.self].state[keyPath: property]
        self.property = property
        
        let updateStream = AsyncStoreRepository.shared[Key.self].stream(for: property)

        Task {
            for await newValue in updateStream {
                Task { @MainActor [weak self] in self?.value = newValue }
            }
        }
    }
    
    public var wrappedValue: Value {
        get { value }
    }
    
    @MainActor
    public func update() {
        value = AsyncStoreRepository.shared[Key.self].state[keyPath: property]
    }
}
