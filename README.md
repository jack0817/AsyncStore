# AsyncStore

A brief description of the framework

## Table of Contents

### 1. Store
#### 1.1 Anatomy of an AsyncStore
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
            .environmentObject(userSTore)
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

        ```json
        {
            "firstName": "John",
            "lastName": "Smith",
            "age": 25
        }
        ```

## Section 2

## Section 3

```ruby
require 'redcarpet'
markdown = Redcarpet.new("Hello World!")
puts markdown.to_html
```

```swift
struct Animal {
    let nickName : String?
}
```
