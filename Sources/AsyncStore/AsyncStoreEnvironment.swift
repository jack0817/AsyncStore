//
//  AsyncStoreEnvironment.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/15/25.
//

import Foundation
import SwiftUI

// MARK: Key - Public API

@MainActor
public protocol AsyncStoreEnvironmentKey: Sendable {
    associatedtype State: Sendable
    associatedtype TaskIdentifier: Hashable, Sendable
    typealias Store = AsyncStore<State, TaskIdentifier>
    static var defaultValue: Store { get }
}

// MARK: Values - Internal API

@MainActor
internal final class AsyncStoreEnvironmentValues {
    static let shared = AsyncStoreEnvironmentValues()
    
    init() {}
    
    private var storage: [ObjectIdentifier: Any] = [:]
    
    subscript<Key: AsyncStoreEnvironmentKey>(_ key: Key.Type) -> Key.Store {
        get { storage[ObjectIdentifier(key)] as? Key.Store ?? Key.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
}

// MARK: SwiftUI Extensions

public extension View {
    func asyncStoreEnvironment<Key: AsyncStoreEnvironmentKey>(
        _ key: Key.Type,
        _ store: Key.Store
    ) -> some View {
        AsyncStoreEnvironmentValues.shared[key] = store
        return environment(AsyncStoreEnvironmentValues.shared[key])
    }
    
    func asyncStoreEnvironment<Key: AsyncStoreEnvironmentKey>(_ key: Key.Type) -> some View {
        return environment(AsyncStoreEnvironmentValues.shared[key])
    }
}
