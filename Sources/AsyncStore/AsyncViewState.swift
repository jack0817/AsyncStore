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

// MARK: Test Code

import SwiftUI

struct TestState: Sendable {
    var text = ""
}

enum TestTaskIdentifier: Hashable, Sendable {
    case one
}

typealias TestStore = AsyncStore<TestState, TestTaskIdentifier>

extension TestStore {
    convenience init(_ state: TestState = .init()) {
        self.init(state: state)
    }
    
    func setValue(to newValue: String) {
        
    }
}

enum TestStoreEnvironmentKey: AsyncStoreEnvironmentKey {
    static let defaultValue: TestStore = .init(state: .init(text: "Hello"))
}

struct TestView: View {
    @State private var viewState = AsyncViewState(
        TestStoreEnvironmentKey.self,
        \.text.isEmpty,
        \.text.count
    )
    
    var body: some View {
        VStack {
            Text(viewState.isEmpty.description)
            Text(viewState.count, format: .number)
        }
    }
}

extension AsyncViewState where Key == TestStoreEnvironmentKey {
    var isEmpty: Bool { AsyncStoreEnvironmentValues.shared[Key.self].state.text.isEmpty }
    var count: Int { AsyncStoreEnvironmentValues.shared[Key.self].state.text.count }
}
