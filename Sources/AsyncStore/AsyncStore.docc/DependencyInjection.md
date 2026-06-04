# Dependency Injection

Provide services to your stores and swap implementations for testing.

## Overview

AsyncStore includes a lightweight dependency injection system based on environment keys. This lets you inject services — such as network clients, persistence layers, or analytics providers — into your stores without hard-coding concrete implementations.

### Define an Environment Key

Create an enum conforming to ``AsyncStoreEnvironmentKey`` with a `defaultValue` that serves as the production fallback:

```swift
protocol UserServiceProvider: Sendable {
    func fetchUser(id: String) async throws -> User
}

struct LiveUserService: UserServiceProvider {
    func fetchUser(id: String) async throws -> User {
        // Real network call
    }
}

enum UserServiceKey: AsyncStoreEnvironmentKey {
    static var defaultValue: UserServiceProvider { LiveUserService() }
}
```

### Register a Convenience Property

Add a computed property on ``AsyncStoreEnvironmentValues`` for ergonomic access:

```swift
extension AsyncStoreEnvironmentValues {
    var userService: UserServiceProvider {
        get { self[UserServiceKey.self] }
        set { self[UserServiceKey.self] = newValue }
    }
}
```

### Use the Environment in Effects

Access the store's environment inside task effects via the ``AsyncStore/env`` property:

```swift
let store = AsyncStore<ProfileState, ProfileTask>(state: ProfileState())

store.run(.task { @Sendable [env = store.env] in
    let user = try await env.userService.fetchUser(id: "123")
    return .set(\.user, to: user)
})
```

> Important: Capture `store.env` in the closure's capture list. Task effects run off the main actor, so you need a local reference to the environment values.

### Inject Mocks for Testing

Create a custom ``AsyncStoreEnvironmentValues`` and override the service before creating the store:

```swift
struct MockUserService: UserServiceProvider {
    let stubbedUser: User

    func fetchUser(id: String) async throws -> User {
        stubbedUser
    }
}

@Test("Store fetches user from injected service")
@MainActor
func fetchUser() async throws {
    let env = AsyncStoreEnvironmentValues()
    env.userService = MockUserService(stubbedUser: User(name: "Test"))

    let store = AsyncStore<ProfileState, ProfileTask>(
        state: ProfileState(),
        environment: env
    )

    store.run(.task { @Sendable [env = store.env] in
        let user = try await env.userService.fetchUser(id: "123")
        return .set(\.user, to: user)
    })

    // Assert that the mock data was applied...
}
```

### Parent-Child Environments

``AsyncStoreEnvironmentValues`` supports a parent-child hierarchy. A child environment inherits all values from its parent but can override specific keys:

```swift
let parent = AsyncStoreEnvironmentValues()
parent.userService = LiveUserService()

let child = parent.child()
child.userService = MockUserService(stubbedUser: testUser)

// child.userService → MockUserService
// parent.userService → LiveUserService (unchanged)
```

This is useful for scoping overrides to a particular feature or test without affecting the global environment.
