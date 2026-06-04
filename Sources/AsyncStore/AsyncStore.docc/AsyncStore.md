# ``AsyncStore``

A lightweight, unidirectional state management framework for SwiftUI built on Swift concurrency.

## Overview

AsyncStore provides a predictable, observable state container that integrates seamlessly with SwiftUI. It uses an effect-based architecture where every state change flows through a single `run(_:)` entry point, making state mutations easy to trace, test, and compose.

The framework is built around four core concepts:

- **State**: A `Sendable` value type that holds your feature's data.
- **Effects**: Declarative descriptions of state changes, async operations, and their composition.
- **Environment**: A dependency injection system for providing services to your store.
- **Repository**: A shared state layer that lets multiple stores observe and react to global data.

```swift
// Define your feature's state
struct CounterState: Sendable {
    var count = 0
}

// Define task identifiers for cancellation
enum CounterTask: Hashable, Sendable {
    case delayedIncrement
}

// Create and use the store
let store = AsyncStore<CounterState, CounterTask>(state: CounterState())
store.run(.set(\.count, to: 1))
```

### Use Cases

AsyncStore is well-suited for a variety of application patterns:

- **Feature-level state management** — Encapsulate the state, business logic, and side effects for a single screen or feature within a dedicated store.
- **Form handling** — Use ``AsyncStore/binding(for:)`` to create two-way SwiftUI bindings backed by the store's state, keeping form logic centralized.
- **Network request orchestration** — Model API calls as `.task` effects, with built-in error handling via ``AsyncStore/mapError`` and automatic cancellation via task identifiers.
- **Cross-feature data sharing** — Register stores in the ``AsyncStoreRepository`` so that multiple features can observe and react to shared state changes in real time.
- **Dependency injection for testing** — Swap out live services for mocks using ``AsyncStoreEnvironmentValues``, enabling fast and deterministic unit tests.

## Topics

### Essentials

- <doc:GettingStarted>
- ``AsyncStore``

### Managing State

- <doc:ManagingState>
- ``AsyncStore/Effect``
- ``AsyncStore/state``
- ``AsyncStore/run(_:)``
- ``AsyncStore/binding(for:)``

### Working with Effects

- <doc:WorkingWithEffects>
- ``AsyncStore/Effect/none``
- ``AsyncStore/Effect/set(_:to:)``
- ``AsyncStore/Effect/task(_:)``
- ``AsyncStore/Effect/concatenate(_:)-4serx``
- ``AsyncStore/Effect/merge(_:)-609xc``
- ``AsyncStore/Effect/append(_:to:)``

### Error Handling

- ``AsyncStore/mapError``

### Dependency Injection

- <doc:DependencyInjection>
- ``AsyncStoreEnvironmentKey``
- ``AsyncStoreEnvironmentValues``
- ``AsyncStore/env``

### Sharing State Across Features

- <doc:SharingStateWithRepository>
- ``AsyncStoreRepositoryKey``
- ``AsyncStoreRepository``
- ``AsyncStore/bind(_:to:map:)``
- ``AsyncStore/repo(for:_:)``
