# AsyncStore

AsyncStores are first and foremost `ObservableObject`s so they can take advantage of all of SwiftUI's environment features including `@EnvironmentObject` and `@StateObject`. An AsyncStore consists of 2 components, State and Environment. State represents the current state of the data domain represented by the Store (i.e. A UserStore's state would house all values and functions pertaining to the User of the app). The enviroment holds all dependencies needed by the Store including services, constants etc. 

**NOTE:** AsyncStores are *not* intended to belong to a single view but rather to mutliple views and can be shared via SwiftUI's environment. 

## Table of Contents

1. [Store](#1-store)
   - [1.1 Anatomy of an AsyncStore](#11-anatomy-of-an-asyncstore)
2. [Effects](#2-effects)
   - [2.1 Effect Composition](#21-effect-composition)
   - [2.2 Task Cancellation](#22-task-cancellation)
3. [Bindings](#3-bindings)
4. [Single Source of Truth](#4-creating-a-single-source-of-truth)
5. [Memory Management](#5-memory-management)

### 1. Store

#### 1.1 Anatomy of an AsyncStore

For the purposes of this README we will be constructing a standard UserStore.

##### State

```swift
struct UserState {
    var user: User? = .none
    var errorDialog: Dialog? = .none
}
```

##### Environment

```swift
struct UserEnvironment {
    let authService = AuthService()
}
```

##### Store

```swift
typealias UserStore = AsyncStore<UserState, UserEnvironment>

extension UserStore {
    convenience init(_ state: UserState = .init()) {
        self.init(
            state: state, 
            env: .init(), 
            mapError: ErrorHandler().mapError
        )
    }
}

// MARK: Public API

extension UserStore {
    func login(_ credentials: Credentials) {
        receive(.dataTask(credentials, loginTask))
    }
    
    func logout() {
        receive(.task(logoutTask))
    }
}

// MARK: Private API (Tasks, Effect mapping, etc..)

fileprivate extension UserStore {
    func loginTask(_ credentials: Credentials) async throws -> Effect {
        let user = try await env.authService.authenticate(
            userName: credentials.userName, 
            password: credentials.password
        )

        return .set(\.user, to: user)
    }
    
    func logoutTask() async throws -> Effect {
        try await env.authService.logout()
        return .set(\.user, to: .none)
    }
}

```

##### Usage

```swift
struct LoginView: View {
    @StateObject private var userStore = UserStore()
    @State private var userName = ""
    @State private var password = ""
    
    private var credentials: Credentials {
        .init(userName: userName, password: password)
    }
    
    private var isLoggedIn: Bool {
        userStore.user != .none
    }
    
    var body: some View {
        VStack {
            TextField("User Name", text: $userName)
            SecureField("Password", text: $password)
            
            if isLoggedIn {
                Button("Logout", action: userStore.logout)
            } else {
                Button("Login", action: { userStore.login(credentials) })
            }
            
            if let dialog = userStore.errorDialog {
                Text(dialog.message)
            }
        }
    }
}
```

##### Error Handling

```swift
fileprivate extension UserStore {
    struct ErrorHandler {
        func mapError(_ error: Error) -> Effect {
            switch error {
            case let authError as AuthenticationError:
                return .set(\.dialog, to: .loginFailed(authError))
            default:
                print("\(error)")
                return .none
            }
        }
    }
}
```

### 2. Effects

Effects are pre-defined actions for the AsyncStore.  Effects begat other effects and are reduced by the AsyncStore until it reaches a void-like effect (i.e. `.none` or a `.set`).
Effects can be sent to an AsyncStore via the `receive` func

```swift
func loadData() {
    receive(.task(loadDataTask))
}
```

| Effect | Description |
| --- | --- |
| `none` | Results in a no-op.  Essentially a void operation |
| `set` | Perform a State mutation on the Main queue.  This will trigger views to render which have property wrappers to AsyncStores |
| `task` | Executes an asynchronous task, Operations must be `async throws -> Effect` |
| `sleep` | Performs a sleep for the specified time. Sleep intervals are not guaranteed to be Exact, but will sleep for *at least* this amount of time. |
| `timer` | Creates an Asynchronous timer that will execute an effect at the specified interval (again, exactness is not guaranteed). |
| `cancel` | Cancels any in-flight task, stream or binding for the specified Idientifier |
| `merge` | Reduces all effects in no particular order |
| `concatenate` | Reduces all effects in sequential order |

#### 2.1 Effect Composition

Because of the recursive nature of Effects, they can be composed via the `merge` and `concatenate` effects.

```swift
func initializeApp() {
    receive(
        .concatenate(
            .set(\.isLoading, to: true),
            .merge(
                .task(loadLocationsTask),
                .task(loadPhotosTask),
                .task(loadFavoritesTask)
            )
            .task(buildSectionsTask),
            .set(\.isLoading, to: false)
        )
    )
}
```

#### 2.2 Task Cancellation

Task and Timer effects can be cancelled by assigning these effects identifiers (of type `AnyHashable`).  To cancel an in-flight effect send the `.cancel(id)` effect to the store.  
**NOTE:** Assigning an identifier will also cancel any existing in-flight task with a **matching** identifier automatically.

```swift
func loadData() {
    recieve(.task(operation: longRunningTask, id: "CancelTask"))
}
```

```swift
func cancelLoad() {
    recieve(.cancel("CancelTask"))
}
```
**NOTE:** Cancelling an in-flight task will cause the task's operation to throw an error of type `CancellationError`. This error will be caught your `mapEffect` function so you can handle it as needed.  [see Error Handling](#Error-Handling)

### 3. Bindings

AsyncStores can bind (or subscribe) to any AsyncSequence and they can create streams for binding purposes either from a state keyPath or from another AsyncStore.

```swift
extension UserStore {
    convenience init(
        _ state: UserState = .init(), 
        env: .init(), 
        mapError: ErrorHandler().mapError
    ) {
        // MARK: Bind to KeyPath
        bind(
            id: "UserStore.searchText", 
            to: \.searchText, 
            mapEffect: mapSearchTextToEffect
        )
        
        // MARK: Bind to AsyncSequence
        bind(
            id: "UserStore.HealthKitService", 
            stream: env.healthKitService().stream()
                .debounce(for: 2.0), 
            mapEffect: mapHealthKitEventToEffect
        )
    }
    
    // MARK: Bind to another AsyncStore
    func bind(to appStore: AppStore) {
        bind(
            id: "UserStore.AppStore.isInitialized", 
            to: appStore, 
            on: \.isInitialized, 
            mapEffect: mapIsAppInitializedToEffect
        )
    }
    
    // MARK: Remove Bindings
    func unbind() {
        let cancelEffects = [
            "UserStore.searchText", 
            "UserStore.HealthKitService", 
            "UserStore.AppStore.isInitialized"
        ].map { id in Effect.cancel(id) }
        receive(.merge(effects: cancelEffects))
    }
}
``` 

### 4. Creating a Single Source of Truth

Stores can be bound to other stores to create a Single Source of Truth.

```swift
struct SSOT: ViewModifier {
    let appStore = AppStore()
    let userStore = UserStore()
    
    init() {
        userStore.bind(to: appStore)
    }
    
    func body(content: Content) -> some View {
        content
            .environmentObject(userStore)
            .environmentObject(appStore)
    }
}
```

```swift
@main
struct MyApp: App {
    @State private var ssot = SSOT()

    var body: some Scene {
        WindowGroup {
            AppView()
                .modifier(ssot)
        }
    }
}
```

### 5. Memory Management

AsyncStore can do a massive amount of Task tracking.  Becuase of this it may become necessary to clean up resources for large AsyncStores that are no longer being used.  To do this simply call the `deactivate` func. Calling `recieve` on a deactivated store will result in a no-op.  To reactivate a store, call `activate`. By default, AsyncStores call `activate` on init.

**NOTE:** Re-activating an AsyncStore *WILL NOT* recreate its previous bindings.  Such bindings will need to be re-instantiated.

```swift
struct ContentView: View {
    @StateObject private var transientStore = TransientStore()
    
    var body: some View {
        VStack {
            Text("Transient Stores")
        }
        .onDisappear {
            transientStore.deactivate()
        }
    }
}
