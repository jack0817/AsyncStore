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
        mapError: { error in 
            return .none
        }
    )
}
```

##### Error Handling

#### 1.2 Example
### 2. Effects
### 3. Creating a Single Source of Truth

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

### 4. Code

## Section 2

## Section 3
