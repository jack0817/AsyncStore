# Managing State

Understand how AsyncStore holds, mutates, and exposes state to SwiftUI views.

## Overview

Every ``AsyncStore`` instance owns a single ``AsyncStore/state`` value. All mutations flow through effects dispatched via ``AsyncStore/run(_:)``, giving you a clear, linear history of how your state changes over time.

### State Is a Value Type

Your state should be a `Sendable` struct. This ensures that state snapshots are safe to pass across concurrency boundaries and that mutations are explicit:

```swift
struct ProfileState: Sendable, Equatable {
    var name = ""
    var email = ""
    var avatarURL: URL?
    var isSaving = false
}
```

### Reading State

The ``AsyncStore/state`` property is read-only from outside the store. AsyncStore supports `@dynamicMemberLookup`, so you can access state properties directly on the store:

```swift
let store = AsyncStore<ProfileState, Never>(state: ProfileState())

// These are equivalent:
let name = store.state.name
let name = store.name
```

In SwiftUI, this means your views read state naturally:

```swift
Text(store.name)
Image(systemName: store.avatarURL != nil ? "person.fill" : "person")
```

### Mutating State

Because ``AsyncStore/state`` is read-only, the only way to change it is by dispatching effects via ``AsyncStore/run(_:)``. The simplest is ``AsyncStore/Effect/set(_:to:)``:

```swift
// Set a single property
store.run(.set(\.name, to: "Alice"))

// Set multiple properties with a closure
store.run(.set { state in
    state.name = "Alice"
    state.email = "alice@example.com"
})
```

There is also ``AsyncStore/Effect/append(_:to:)`` for appending to array properties:

```swift
store.run(.append("New item", to: \.items))
```

### Two-Way Bindings

Use ``AsyncStore/binding(for:)`` to create a SwiftUI `Binding` backed by the store:

```swift
TextField("Name", text: store.binding(for: \.name))
```

The binding reads from and writes to the store's state. Writes are propagated to any active state streams, keeping reactive bindings in sync.

### Observation

`AsyncStore` is marked with `@Observable`, so SwiftUI views that read store properties automatically subscribe to changes. No `ObservableObject`, `@Published`, or manual `objectWillChange` calls are needed:

```swift
struct ProfileView: View {
    @State private var store = AsyncStore<ProfileState, Never>(
        state: ProfileState()
    )

    var body: some View {
        // SwiftUI re-renders this view when `name` or `isSaving` changes.
        VStack {
            Text(store.name)
            if store.isSaving {
                ProgressView()
            }
        }
    }
}
```
