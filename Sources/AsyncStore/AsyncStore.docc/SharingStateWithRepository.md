# Sharing State with the Repository

Use the repository to share state across features and react to global changes.

## Overview

While each ``AsyncStore`` manages its own local state, many apps need a way to share data across unrelated features — for example, the currently logged-in user, a shopping cart, or a set of feature flags. The ``AsyncStoreRepository`` provides a singleton registry where you can store and look up shared stores by key.

### Define a Repository Key

Create an enum conforming to ``AsyncStoreRepositoryKey`` that declares the shared store's state and task identifier types:

```swift
struct SessionState: Sendable {
    var currentUser: User?
    var isAuthenticated = false
    var accessToken: String?
}

enum SessionTask: Hashable, Sendable {
    case refreshToken
    case login
}

enum SessionStoreKey: AsyncStoreRepositoryKey {
    typealias State = SessionState
    typealias TaskIdentifier = SessionTask
}
```

### Register a Convenience Accessor

Add a property on ``AsyncStoreRepository`` for ergonomic access:

```swift
extension AsyncStoreRepository {
    var session: AsyncStore<SessionState, SessionTask> {
        get { self[SessionStoreKey.self] }
        set { self[SessionStoreKey.self] = newValue }
    }
}
```

### Register the Shared Store

Typically at app launch, create the shared store and register it:

```swift
@main
struct MyApp: App {
    init() {
        AsyncStoreRepository.shared.session = AsyncStore(
            state: SessionState()
        )
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### Read from the Repository

Any store can read the current value of a shared store's property using ``AsyncStore/repo(for:_:)``:

```swift
let isAuthenticated = store.repo(for: SessionStoreKey.self, \.isAuthenticated)
```

### Bind to Repository Changes

Use ``AsyncStore/bind(_:to:map:)`` to reactively observe a shared store's property. When the observed property changes, the `map` closure converts the new value into an effect that is dispatched on the local store:

```swift
// In a profile feature store, sync the current user from the session
store.bind(
    SessionStoreKey.self,
    to: \.currentUser,
    map: { user in
        .set(\.displayName, to: user?.name ?? "Guest")
    }
)
```

Key behaviors of `bind`:

- **Automatic deduplication**: Duplicate values are filtered, so the `map` closure only fires on actual changes.
- **Multiple bindings**: A single store can bind to multiple properties from the same or different repository keys.
- **Cleanup on deinit**: When the consumer store is deallocated, all its bindings are automatically cancelled.

### Use Case: Cross-Feature Synchronization

Consider an e-commerce app where a cart badge in the tab bar needs to reflect the cart count managed by a separate cart feature:

```swift
// Cart repository key
enum CartStoreKey: AsyncStoreRepositoryKey {
    typealias State = CartState
    typealias TaskIdentifier = CartTask
}

// Tab bar store binds to the cart item count
tabBarStore.bind(
    CartStoreKey.self,
    to: \.items,
    map: { items in
        .set(\.cartBadgeCount, to: items.count)
    }
)
```

When items are added or removed in the cart feature, the tab bar store automatically updates its badge count — no manual coordination needed.

### Use Case: Authentication-Gated Features

Bind to the session store to react when a user logs in or out:

```swift
store.bind(
    SessionStoreKey.self,
    to: \.isAuthenticated,
    map: { isAuthenticated in
        if isAuthenticated {
            return .task {
                let profile = try await api.fetchProfile()
                return .set(\.profile, to: profile)
            }
        } else {
            return .set { state in
                state.profile = nil
                state.favorites = []
            }
        }
    }
)
```

The binding fires complex effects — including async work — in response to global state changes, keeping feature stores reactive without tight coupling.
