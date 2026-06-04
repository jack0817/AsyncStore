//
//  AsyncStoreEnvironment.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import Foundation

/// A protocol for defining keys in the store's dependency injection system.
///
/// Conform to this protocol to register a service or value that stores can access
/// through ``AsyncStoreEnvironmentValues``. Provide a `defaultValue` that serves
/// as the production fallback.
@MainActor public protocol AsyncStoreEnvironmentKey {
    /// The type of the value associated with this key.
    associatedtype Value
    /// The default value returned when no custom value has been set.
    static var defaultValue: Value { get }
}

/// A container for dependency values that can be injected into stores.
///
/// Environment values support a parent-child hierarchy. A child inherits all values
/// from its parent but can override specific keys without affecting the parent.
@MainActor
public final class AsyncStoreEnvironmentValues {
    /// The shared default environment instance.
    public static let shared = AsyncStoreEnvironmentValues()
    
    private var parent: AsyncStoreEnvironmentValues?
    private var storage: [ObjectIdentifier: Any] = [:]
    
    init(parent: AsyncStoreEnvironmentValues?) {
        self.parent = parent
    }
    
    convenience init() {
        self.init(parent: .none)
    }
    
    public subscript<Key: AsyncStoreEnvironmentKey>(_ key: Key.Type) -> Key.Value {
        get {
            let id = ObjectIdentifier(key)
            return storage[id] as? Key.Value
                ?? parent?.storage[id] as? Key.Value
                ?? key.defaultValue
        }
        set {
            let id = ObjectIdentifier(key)
            storage[id] = newValue
        }
    }
    
    func child() -> AsyncStoreEnvironmentValues {
        .init(parent: self)
    }
}
