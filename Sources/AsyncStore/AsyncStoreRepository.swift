//
//  AsyncStoreRepository.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import Foundation
import SwiftUI

public protocol AsyncStoreRepositoryKey {
    associatedtype State: Sendable
    associatedtype TaskIdentifier: Sendable & Hashable
    typealias Store = AsyncStore<State, TaskIdentifier>
}

public final class AsyncStoreRepository {
    @MainActor
    internal static let shared = AsyncStoreRepository()
    
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
