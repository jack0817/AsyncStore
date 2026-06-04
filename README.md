# AsyncStore

A lightweight, unidirectional state management framework for SwiftUI built on Swift concurrency.

## Overview

AsyncStore provides a predictable, observable state container where every mutation flows through a single `run(_:)` entry point. It integrates with SwiftUI's `@Observable` macro for automatic view updates and runs async work off the main thread.

```swift
struct CounterState: Sendable {
    var count = 0
}

enum CounterTask: Hashable, Sendable {
    case delayedIncrement
}

let store = AsyncStore<CounterState, CounterTask>(state: CounterState())

// Synchronous state mutation
store.run(.set(\.count, to: 1))

// Async operation with automatic cancellation
store.run(.task(param: 10, id: .delayedIncrement) { amount in
    try await Task.sleep(for: .seconds(1))
    return .set(\.count, to: amount)
})
```

## Requirements

- Swift 6.2+
- macOS 26+ / iOS 26+ / tvOS 26+ / watchOS 26+

## Installation

Add AsyncStore as a Swift Package Manager dependency:

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/AsyncStore", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "MyApp",
    dependencies: ["AsyncStore"]
)
```

## Core Concepts

### State

A `Sendable` value type that holds your feature's data:

```swift
struct ProfileState: Sendable {
    var name = ""
    var isLoading = false
    var errorMessage: String?
}
```

### Effects

Declarative descriptions of state changes dispatched via `run(_:)`:

| Effect | Description |
|--------|-------------|
| `.none` | No-op |
| `.set` | Synchronous state mutation |
| `.task` | Async operation that returns a new effect |
| `.concatenate` | Sequential effect composition |
| `.merge` | Concurrent effect composition |

### Environment

A dependency injection system for providing services and swapping mocks in tests:

```swift
enum UserServiceKey: AsyncStoreEnvironmentKey {
    static var defaultValue: UserServiceProvider { LiveUserService() }
}

extension AsyncStoreEnvironmentValues {
    var userService: UserServiceProvider {
        get { self[UserServiceKey.self] }
        set { self[UserServiceKey.self] = newValue }
    }
}
```

### Repository

A shared state registry that enables cross-feature data sharing with reactive bindings:

```swift
store.bind(SessionStoreKey.self, to: \.currentUser, map: { user in
    .set(\.displayName, to: user?.name ?? "Guest")
})
```

## SwiftUI Integration

AsyncStore is `@Observable` and supports `@dynamicMemberLookup`, so views read state naturally:

```swift
struct ProfileView: View {
    @State private var store = AsyncStore<ProfileState, ProfileTask>(
        state: ProfileState()
    )

    var body: some View {
        VStack {
            TextField("Name", text: store.binding(for: \.name))
            if store.isLoading {
                ProgressView()
            }
        }
        .task {
            store.run(.task({
                let profile = try await env.userService.fetchProfile()
                return .set(\.name, to: profile.name)
            }, id: .fetchProfile))
        }
    }
}
```

## Documentation

Full API documentation is available as a DocC catalog included in the package. Build documentation in Xcode via **Product > Build Documentation** or from the command line:

```bash
swift package generate-documentation --target AsyncStore
```

The documentation includes these guides:

- **Getting Started** — Define state, create a store, dispatch effects, connect to SwiftUI
- **Managing State** — Dynamic member lookup, bindings, observation
- **Working with Effects** — Task cancellation, error handling, sequential and concurrent composition
- **Dependency Injection** — Environment keys, mock injection, parent-child environments
- **Sharing State with the Repository** — Cross-feature bindings, reactive synchronization

## License

See [LICENSE](LICENSE) for details.
