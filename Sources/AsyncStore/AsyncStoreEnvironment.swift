//
//  AsyncStoreEnvironment.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import Foundation

@MainActor public protocol AsyncStoreEnvironmentKey {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
}

@MainActor
public final class AsyncStoreEnvironmentValues {
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
