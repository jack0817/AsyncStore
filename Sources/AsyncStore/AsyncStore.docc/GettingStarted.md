# Getting Started with AsyncStore

Set up your first store and drive a SwiftUI view with unidirectional state management.

## Overview

AsyncStore follows a simple pattern: define your state, create a store, and dispatch effects to mutate that state. SwiftUI views observe the store automatically thanks to the `@Observable` macro.

### Define Your State

Start by declaring a `Sendable` struct that holds the data for your feature:

```swift
struct TodoListState: Sendable {
    var todos: [TodoItem] = []
    var isLoading = false
    var errorMessage: String?
}
```

### Choose Task Identifiers

Task identifiers let you cancel in-flight async work. Define an enum that conforms to `Hashable` and `Sendable`:

```swift
enum TodoListTask: Hashable, Sendable {
    case fetchTodos
    case saveTodo
}
```

### Create the Store

Instantiate an ``AsyncStore`` with your state and task identifier types:

```swift
let store = AsyncStore<TodoListState, TodoListTask>(
    state: TodoListState()
)
```

### Dispatch Effects

Use ``AsyncStore/run(_:)`` to send effects to the store. Effects describe *what should happen* — the store handles *when and how*.

```swift
// Set a property directly
store.run(.set(\.isLoading, to: true))

// Run an async operation
store.run(.task({
    let todos = try await api.fetchTodos()
    return .set(\.todos, to: todos)
}, id: .fetchTodos))
```

### Connect to SwiftUI

Because `AsyncStore` is `@Observable`, SwiftUI views automatically re-render when state changes. Use `@State` to own the store and `@dynamicMemberLookup` to access state properties directly:

```swift
struct TodoListView: View {
    @State private var store = AsyncStore<TodoListState, TodoListTask>(
        state: TodoListState()
    )

    var body: some View {
        List(store.todos) { todo in
            Text(todo.title)
        }
        .overlay {
            if store.isLoading {
                ProgressView()
            }
        }
        .task {
            store.run(.task({
                let todos = try await TodoService.fetchAll()
                return .concatenate(
                    .set(\.todos, to: todos),
                    .set(\.isLoading, to: false)
                )
            }, id: .fetchTodos))
        }
    }
}
```

### Two-Way Bindings

For forms and interactive controls, create bindings with ``AsyncStore/binding(for:)``:

```swift
struct SettingsView: View {
    @State private var store = AsyncStore<SettingsState, Never>(
        state: SettingsState()
    )

    var body: some View {
        Toggle(
            "Dark Mode",
            isOn: store.binding(for: \.isDarkMode)
        )
    }
}
```

### Handle Errors

Assign a closure to ``AsyncStore/mapError`` to convert thrown errors into effects:

```swift
store.mapError = { error in
    .set(\.errorMessage, to: error.localizedDescription)
}
```

Any error thrown inside a `.task` effect is caught and routed through this handler. If no handler is set, errors are silently mapped to `.none`.
