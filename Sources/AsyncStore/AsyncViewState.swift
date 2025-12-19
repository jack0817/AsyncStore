//
//  AsyncViewState.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/15/25.
//

import Foundation

@MainActor
@Observable
public final class AsyncViewState<Key: AsyncStoreEnvironmentKey, each Value: Equatable & Sendable> {
    public init(
        _ key: Key.Type,
        _ properties: repeat KeyPath<Key.State, each Value>
    ) {
        for property in repeat each properties {
            observe(property)
        }
        
        func observe<Property: Equatable & Sendable>(_ property: KeyPath<Key.State, Property>) {
            let desc = property.debugDescription
            withObservationTracking(
                { _ = AsyncStoreEnvironmentValues
                        .shared[Key.self]
                        .state[keyPath: property] },
                onChange: {
                    print("[OBSERVED] change to \(desc)")
                }
            )
        }
    }
}
