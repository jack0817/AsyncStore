# AsyncStore

A brief description of the framework

## Table of Contents

### 1. Store

An AsyncStore consists of 2 components, State and Environment. State represents the current state of the data domain represented by the Store (i.e. A UserStore's state would house all values pertaining the User model). The enviroment holds all dependencies needed by the Store including services, constants etc. 

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
    convenience init(
        _ state: UserState = .init(), 
        env: .init(), 
        mapError: ErrorHandler().mapError
    )
}

// MARK: Public API

extension UserStore {
    func login(_ credentials: Credientials) {
        receive(.dataTask(credentials, loginTask))
    }
    
    func logout() {
        receive(.task(logoutTask))
    }
}

// MARK: Private API (Tasks, Effect mapping, etc..)

fileprivate extension UserStore {
    func loginTask(_ credentials: Credientials) async throws -> Effect {
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

#### 2.1 Effect Composition

### 3. Bindings

### 4. Creating a Single Source of Truth

Stores can be bound to other stores.

```swift
struct SSOT: ViewModifier {
    let appStore = AppStore()
    let userStore = UserStore()
    
    init() {
        userStore.bind(to: appStore)
    }
    
    func body(content: Content) -> some View {
        content.
            .environmentObject(userStore)
            .environmentObject(appStore)
    }
}
```

```swift
@main
struct MyApp: App {
    @StateObject private var ssot = SSOT()

    var body: some Scene {
        WindowGroup {
            AppView()
                .modifier(ssot)
        }
    }
}
```
