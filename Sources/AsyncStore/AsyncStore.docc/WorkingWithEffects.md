# Working with Effects

Compose synchronous state changes, async operations, and complex effect chains.

## Overview

``AsyncStore/Effect`` is the core building block of AsyncStore. Every interaction — a button tap, a network response, a timer firing — is expressed as an effect dispatched via ``AsyncStore/run(_:)``. Effects are an enum with five cases that cover the full range of state management needs.

### None

The `.none` effect is a no-op. It is useful as a default return value or terminal case:

```swift
store.run(.none) // Does nothing
```

### Set

The `.set` effect mutates state synchronously. There are two forms:

```swift
// KeyPath form — set a single property
store.run(.set(\.isLoading, to: true))

// Closure form — mutate multiple properties at once
store.run(.set { state in
    state.isLoading = false
    state.errorMessage = nil
    state.results = fetchedResults
})
```

### Task

The `.task` effect runs an asynchronous operation off the main thread and returns a new effect to apply when it completes:

```swift
store.run(.task {
    let user = try await api.fetchCurrentUser()
    return .set(\.user, to: user)
})
```

#### Passing Parameters

Use ``AsyncStore/Effect/task(param:id:_:)`` to capture a `Sendable` parameter:

```swift
store.run(.task(param: searchQuery, id: .search) { query in
    let results = try await api.search(query)
    return .set(\.results, to: results)
})
```

#### Task Identifiers and Cancellation

When you provide a task identifier, the store automatically cancels any in-flight task with the same ID before starting the new one. This is essential for search-as-you-type and other debounce patterns:

```swift
enum SearchTask: Hashable, Sendable {
    case search
}

// Each keystroke cancels the previous search
store.run(.task(param: query, id: .search) { query in
    let results = try await api.search(query)
    return .set(\.results, to: results)
})
```

#### Error Handling

Errors thrown inside a `.task` are caught and routed through ``AsyncStore/mapError``. If no handler is set, the error maps to `.none`:

```swift
store.mapError = { error in
    .set(\.errorMessage, to: error.localizedDescription)
}
```

### Concatenate

The `.concatenate` effect runs a sequence of effects one after another. Each effect completes before the next one starts:

```swift
store.run(.concatenate(
    .set(\.isLoading, to: true),
    .task {
        let data = try await api.fetchData()
        return .set(\.data, to: data)
    },
    .set(\.isLoading, to: false)
))
```

This guarantees ordering: `isLoading` becomes `true`, the network call finishes, and then `isLoading` becomes `false`.

### Merge

The `.merge` effect runs multiple effects concurrently. All effects start at the same time and complete independently:

```swift
store.run(.merge(
    .task {
        let user = try await api.fetchUser()
        return .set(\.user, to: user)
    },
    .task {
        let settings = try await api.fetchSettings()
        return .set(\.settings, to: settings)
    }
))
```

Use `.merge` when effects are independent and you want maximum parallelism.

### Composing Effects

Effects compose naturally. You can nest `.concatenate` inside `.merge` or vice versa to build sophisticated workflows:

```swift
// Fetch user and settings in parallel, then update the UI
store.run(.concatenate(
    .set(\.isLoading, to: true),
    .merge(
        .task {
            let user = try await api.fetchUser()
            return .set(\.user, to: user)
        },
        .task {
            let prefs = try await api.fetchPreferences()
            return .set(\.preferences, to: prefs)
        }
    ),
    .set(\.isLoading, to: false)
))
```
