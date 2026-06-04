import Foundation
import Testing
@testable import AsyncStore

extension Tag {
    @Tag static var store: Self
    @Tag static var effects: Self
    @Tag static var environment: Self
    @Tag static var repository: Self
}

// MARK: - Initialization

@Suite("AsyncStore Initialization", .tags(.store))
struct AsyncStoreInitTests {
    @MainActor
    @Test("Store initializes with the provided state")
    func initWithState() {
        let store = TestStore(state: TestState(ints: [1, 2, 3]))
        #expect(store.state.ints == [1, 2, 3])
        #expect(store.state.strings == [])
        #expect(store.state.error == nil)
    }
    
    @MainActor
    @Test("Store initializes with default state via convenience init")
    func initWithDefaults() {
        let store = TestStore()
        #expect(store.state == TestState())
    }
    
    @MainActor
    @Test("Store initializes with a custom environment")
    func initWithCustomEnvironment() {
        let env = AsyncStoreEnvironmentValues()
        env.testService = .mock([10, 20])
        let store = TestStore(environment: env)
        #expect(store.env === env)
    }
}

// MARK: - Dynamic Member Lookup

@Suite("AsyncStore DynamicMemberLookup", .tags(.store))
struct AsyncStoreDynamicMemberLookupTests {
    @MainActor
    @Test("Dynamic member lookup returns state properties")
    func dynamicMemberLookup() {
        let store = TestStore(state: TestState(ints: [5], strings: ["hello"]))
        #expect(store.ints == [5])
        #expect(store.strings == ["hello"])
    }
}

// MARK: - Set Effect

@Suite("AsyncStore Set Effect", .tags(.effects))
struct AsyncStoreSetEffectTests {
    @MainActor
    @Test("Set effect mutates state with a closure")
    func setWithClosure() async throws {
        let store = TestStore()
        try await StoreWaiter(store: store)
            .wait(for: \.ints, running: .set { $0.ints = [1, 2, 3] })
            .expect(\.ints, toEqual: [1, 2, 3])
    }
    
    @MainActor
    @Test("Set effect mutates state with a keypath and value")
    func setWithKeyPath() async throws {
        let store = TestStore()
        try await StoreWaiter(store: store)
            .wait(for: \.strings, running: .set(\.strings, to: ["a", "b"]))
            .expect(\.strings, toEqual: ["a", "b"])
    }
    
    @MainActor
    @Test("Append effect adds an element to an array property")
    func appendEffect() async throws {
        let store = TestStore(state: TestState(ints: [1]))
        try await StoreWaiter(store: store)
            .wait(for: \.ints, running: .append(2, to: \.ints))
            .expect(\.ints, toEqual: [1, 2])
    }
}

// MARK: - Task Effect

@Suite("AsyncStore Task Effect", .tags(.effects))
struct AsyncStoreTaskEffectTests {
    @MainActor
    @Test("Task effect executes an async operation and applies the result")
    func taskEffect() async throws {
        let store = TestStore()
        let effect: TestStore.Effect = .task {
            .set(\.ints, to: [42])
        }
        try await StoreWaiter(store: store)
            .wait(for: \.ints, running: effect)
            .expect(\.ints, toEqual: [42])
    }
    
    @MainActor
    @Test("Task effect with param passes the parameter to the operation")
    func taskWithParam() async throws {
        let store = TestStore()
        let effect: TestStore.Effect = .task(param: 99) { value in
            .set(\.ints, to: [value])
        }
        try await StoreWaiter(store: store)
            .wait(for: \.ints, running: effect)
            .expect(\.ints, toEqual: [99])
    }
    
    @MainActor
    @Test("Task effect with id cancels previous task with the same id")
    func taskCancelsPreviousWithSameId() async throws {
        let store = TestStore()
        let counter = Counter()
        
        // Merge allows both tasks to reduce concurrently. The slow task
        // starts first; then the fast task with the same id cancels it
        // via `track`.
        let effect: TestStore.Effect = .merge([
            .task({ @Sendable in
                try await Task.sleep(for: .seconds(10))
                await counter.increment()
                return .none
            }, id: .one),
            .task({ @Sendable in
                // Small delay so the slow task registers first
                try await Task.sleep(for: .milliseconds(100))
                return .set(\.ints, to: [1])
            }, id: .one),
        ])
        
        try await StoreWaiter(store: store)
            .wait(for: \.ints, running: effect)
            .expect(\.ints, toEqual: [1])
        
        // Give some time for the slow task to have potentially completed
        try await Task.sleep(for: .milliseconds(200))
        let count = await counter.count
        #expect(count == 0, "The first task should have been cancelled")
    }
}

// MARK: - Concatenate Effect

@Suite("AsyncStore Concatenate Effect", .tags(.effects))
struct AsyncStoreConcatenateEffectTests {
    @MainActor
    @Test("Concatenate runs effects sequentially")
    func concatenateEffects() async throws {
        let store = TestStore()
        let effect: TestStore.Effect = .concatenate([
            .set(\.ints, to: [1]),
            .set(\.strings, to: ["done"]),
        ])
        try await StoreWaiter(store: store)
            .wait(for: \.strings, running: effect)
            .expect(\.ints, toEqual: [1])
            .expect(\.strings, toEqual: ["done"])
    }
    
    @MainActor
    @Test("Concatenate preserves order of async tasks")
    func concatenatePreservesOrder() async throws {
        let store = TestStore()
        let effect: TestStore.Effect = .concatenate([
            .task {
                try await Task.sleep(for: .milliseconds(50))
                return .append(1, to: \.ints)
            },
            .task {
                .append(2, to: \.ints)
            },
        ])
        try await StoreWaiter(store: store)
            .wait(for: \.ints, count: 2, running: effect)
            .expect(\.ints, toEqual: [1, 2])
    }
}

// MARK: - Merge Effect

@Suite("AsyncStore Merge Effect", .tags(.effects))
struct AsyncStoreMergeEffectTests {
    @MainActor
    @Test("Merge runs effects concurrently")
    func mergeEffects() async throws {
        let store = TestStore()
        let effect: TestStore.Effect = .merge([
            .set(\.ints, to: [1]),
            .set(\.strings, to: ["merged"]),
        ])
        // Both properties should be set after merge completes
        try await StoreWaiter(store: store)
            .wait(for: \.strings, running: effect)
            .expect(\.ints, toEqual: [1])
            .expect(\.strings, toEqual: ["merged"])
    }
}

// MARK: - MapError

@Suite("AsyncStore MapError", .tags(.effects))
struct AsyncStoreMapErrorTests {
    @MainActor
    @Test("mapError converts thrown errors into effects")
    func mapErrorHandlesThrow() async throws {
        let store = TestStore()
        store.mapError = { error in
            .set(\.error, to: .test)
        }
        
        let effect: TestStore.Effect = .task {
            throw TestError.test
        }
        
        try await StoreWaiter(store: store)
            .wait(for: \.error, running: effect)
            .expect(\.error, toEqual: .test)
    }
    
    @MainActor
    @Test("mapError defaults to .none, leaving state unchanged on throw")
    func mapErrorDefaultsToNone() async throws {
        let store = TestStore()
        
        // Run an effect that throws without setting mapError
        let effect: TestStore.Effect = .task {
            throw TestError.test
        }
        store.run(effect)
        
        // Give time for the task to be processed
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.state.error == nil)
    }
}

// MARK: - Binding

@Suite("AsyncStore Binding", .tags(.store))
struct AsyncStoreBindingTests {
    @MainActor
    @Test("Binding reads the current value from state")
    func bindingGet() {
        let store = TestStore(state: TestState(ints: [1, 2]))
        let binding = store.binding(for: \.ints)
        #expect(binding.wrappedValue == [1, 2])
    }
    
    @MainActor
    @Test("Binding writes a new value to state")
    func bindingSet() {
        let store = TestStore()
        let binding = store.binding(for: \.strings)
        binding.wrappedValue = ["updated"]
        #expect(store.state.strings == ["updated"])
    }
}

// MARK: - Environment

@Suite("AsyncStoreEnvironment", .tags(.environment))
struct AsyncStoreEnvironmentTests {
    @MainActor
    @Test("Environment returns default value for an unset key")
    func environmentDefault() {
        let env = AsyncStoreEnvironmentValues()
        let service = env.testService
        // Default EmptyTestService returns []
        #expect(service is EmptyTestService)
    }
    
    @MainActor
    @Test("Environment stores and retrieves a custom value")
    func environmentCustomValue() {
        let env = AsyncStoreEnvironmentValues()
        env.testService = .mock([1, 2, 3])
        #expect(env.testService is MockTestService)
    }
    
    @MainActor
    @Test("Child environment inherits from parent")
    func childInheritsFromParent() {
        let parent = AsyncStoreEnvironmentValues()
        parent.testService = .mock([10])
        let child = parent.child()
        #expect(child.testService is MockTestService)
    }
    
    @MainActor
    @Test("Child environment can override parent values")
    func childOverridesParent() {
        let parent = AsyncStoreEnvironmentValues()
        parent.testService = .mock([10])
        let child = parent.child()
        child.testService = .empty
        #expect(child.testService is EmptyTestService)
        // Parent retains its value
        #expect(parent.testService is MockTestService)
    }
    
    @MainActor
    @Test("Store uses injected environment service in task effects")
    func storeUsesEnvironmentService() async throws {
        let env = AsyncStoreEnvironmentValues()
        env.testService = .mock([7, 8, 9])
        let store = TestStore(environment: env)
        
        let effect: TestStore.Effect = .task { @Sendable [env = store.env] in
            let ints = try await env.testService.getInts()
            return .set(\.ints, to: ints)
        }
        
        try await StoreWaiter(store: store)
            .wait(for: \.ints, running: effect)
            .expect(\.ints, toEqual: [7, 8, 9])
    }
}

// MARK: - Deinit

@Suite("AsyncStore Deinit", .tags(.store))
struct AsyncStoreDeinitTests {
    @MainActor
    @Test("Store is deallocated when all references are released")
    func storeDeallocates() async throws {
        weak var weakStore: TestStore?
        
        autoreleasepool {
            let store = TestStore()
            weakStore = store
            #expect(weakStore != nil)
        }
        
        // Allow pending tasks to drain
        await Task.yield()
        #expect(weakStore == nil, "Store should be deallocated after autoreleasepool")
    }
    
    @MainActor
    @Test("Store cancels running tasks on deinit")
    func storeCancelsTasksOnDeinit() async throws {
        let counter = Counter()
        
        autoreleasepool {
            let store = TestStore()
            // Launch a long-running task
            store.run(.task({ @Sendable in
                try await Task.sleep(for: .seconds(10))
                await counter.increment()
                return .none
            }, id: .one))
        }
        
        // Allow deinit to run and tasks to notice cancellation
        try await Task.sleep(for: .milliseconds(200))
        let count = await counter.count
        #expect(count == 0, "Long-running task should have been cancelled by deinit")
    }
    
    @MainActor
    @Test("Store finishes state continuations on deinit")
    func storeFinishesContinuationsOnDeinit() async throws {
        var streamIterator: AsyncMapSequence<AsyncStream<TestState>, [Int]>.AsyncIterator!
        
        autoreleasepool {
            let store = TestStore()
            let stream = store.stream(for: \.ints)
            streamIterator = stream.makeAsyncIterator()
        }
        
        // The stream should yield the initial value then terminate
        let first = await streamIterator.next()
        #expect(first == [])
        
        let afterDeinit = await streamIterator.next()
        #expect(afterDeinit == nil, "Stream should terminate after store deinit")
    }
}

// MARK: - None Effect

@Suite("AsyncStore None Effect", .tags(.effects))
struct AsyncStoreNoneEffectTests {
    @MainActor
    @Test("None effect does not change state")
    func noneEffect() async throws {
        let store = TestStore(state: TestState(ints: [1]))
        store.run(.none)
        
        // Give the run loop time to process
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.state.ints == [1])
    }
}

// MARK: - Repository

@Suite("AsyncStore Repository", .tags(.repository), .serialized)
struct AsyncStoreRepositoryTests {
    @MainActor
    @Test("Repo - Read value from repository")
    func repoReadValue() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [1, 2, 3], strings: ["A", "B"]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        // Create a consumer store that reads from repo
        let consumerStore = TestStore()
        
        // Read values from repository
        let ints = consumerStore.repo(for: TestStoreRepositoryKey.self, \.ints)
        let strings = consumerStore.repo(for: TestStoreRepositoryKey.self, \.strings)
        
        #expect(ints == [1, 2, 3])
        #expect(strings == ["A", "B"])
    }
    
    @MainActor
    @Test("Repo - Read value after repository update")
    func repoReadAfterUpdate() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [1]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        // Create a consumer store
        let consumerStore = TestStore()
        
        // Read initial value
        let initialValue = consumerStore.repo(for: TestStoreRepositoryKey.self, \.ints)
        #expect(initialValue == [1])
        
        // Update repository
        repoStore.run(.set(\.ints, to: [10, 20, 30]))
        
        // Wait for state to settle
        try await Task.sleep(for: .milliseconds(50))
        
        // Read updated value
        let updatedValue = consumerStore.repo(for: TestStoreRepositoryKey.self, \.ints)
        #expect(updatedValue == [10, 20, 30])
    }
    
    @MainActor
    @Test("Bind - React to repository changes")
    func bindAndReactToChanges() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [1]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        // Create a consumer store that binds to repo
        let consumerStore = TestStore()
        
        // Bind repo changes to consumer store
        consumerStore.bind(
            TestStoreRepositoryKey.self,
            to: \.ints,
            map: { newInts in
                .set(\.strings, to: newInts.map(String.init))
            }
        )
        
        // Wait for binding to establish
        try await Task.sleep(for: .milliseconds(50))
        
        // Update repository store
        try await StoreWaiter(store: consumerStore)
            .wait(for: \.strings, running: { _ in
                repoStore.run(.set(\.ints, to: [1, 2, 3]))
            })
            .expect(\.strings, toEqual: ["1", "2", "3"])
    }
    
    @MainActor
    @Test("Bind - Multiple consumers to same repository")
    func bindMultipleConsumers() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [10], strings: ["X"]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        // Create two consumer stores
        let consumer1 = TestStore()
        let consumer2 = TestStore()
        
        // Bind both consumers to different properties
        consumer1.bind(
            TestStoreRepositoryKey.self,
            to: \.ints,
            map: { .set(\.ints, to: $0) }
        )
        
        consumer2.bind(
            TestStoreRepositoryKey.self,
            to: \.strings,
            map: { .set(\.strings, to: $0) }
        )
        
        // Wait for bindings to establish
        try await Task.sleep(for: .milliseconds(50))
        
        // Update repository - both consumers should react
        try await StoreWaiter(store: consumer1)
            .wait(for: \.ints, running: { _ in
                repoStore.run(.set(\.ints, to: [20, 30]))
            })
            .expect(\.ints, toEqual: [20, 30])
        
        try await StoreWaiter(store: consumer2)
            .wait(for: \.strings, running: { _ in
                repoStore.run(.set(\.strings, to: ["Y", "Z"]))
            })
            .expect(\.strings, toEqual: ["Y", "Z"])
    }
    
    @MainActor
    @Test("Bind - Transform mapped values")
    func bindWithTransform() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [1, 2, 3]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        // Create a consumer store
        let consumerStore = TestStore()
        
        // Bind repo with a transformation (sum of ints)
        consumerStore.bind(
            TestStoreRepositoryKey.self,
            to: \.ints,
            map: { ints in
                let sum = ints.reduce(0, +)
                return .set(\.ints, to: [sum])
            }
        )
        
        // Wait for binding to establish
        try await Task.sleep(for: .milliseconds(50))
        
        // Update repository store
        try await StoreWaiter(store: consumerStore)
            .wait(for: \.ints, running: { _ in
                repoStore.run(.set(\.ints, to: [5, 10, 15]))
            })
            .expect(\.ints, toEqual: [30])
    }
    
    @MainActor
    @Test("Bind - Filters duplicate values")
    func bindFiltersDuplicates() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [1]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        // Create a consumer store with a counter
        let consumerStore = TestStore()
        let counter = Counter()
        
        // Bind repo and count updates
        consumerStore.bind(
            TestStoreRepositoryKey.self,
            to: \.ints,
            map: { ints in
                Task { await counter.increment() }
                return .set(\.ints, to: ints)
            }
        )
        
        // Wait for binding to establish
        try await Task.sleep(for: .milliseconds(50))
        let initialCount = await counter.count
        
        // Update with same value multiple times
        repoStore.run(.set(\.ints, to: [1]))
        try await Task.sleep(for: .milliseconds(50))
        repoStore.run(.set(\.ints, to: [1]))
        try await Task.sleep(for: .milliseconds(50))
        
        // Should not trigger additional updates due to removeDuplicates()
        let afterDuplicatesCount = await counter.count
        #expect(afterDuplicatesCount == initialCount)
        
        // Update with different value
        try await StoreWaiter(store: consumerStore)
            .wait(for: \.ints, running: { _ in
                repoStore.run(.set(\.ints, to: [2]))
            })
        
        // Should trigger exactly one more update
        let finalCount = await counter.count
        #expect(finalCount == initialCount + 1)
    }
    
    @MainActor
    @Test("Bind - Multiple bindings on same consumer")
    func bindMultipleProperties() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [1], strings: ["A"]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        // Create a consumer store
        let consumerStore = TestStore()
        
        // Bind multiple properties from the same repo
        consumerStore.bind(
            TestStoreRepositoryKey.self,
            to: \.ints,
            map: { .set(\.ints, to: $0) }
        )
        
        consumerStore.bind(
            TestStoreRepositoryKey.self,
            to: \.strings,
            map: { .set(\.strings, to: $0) }
        )
        
        // Wait for bindings to establish
        try await Task.sleep(for: .milliseconds(50))
        
        // Update both properties
        try await StoreWaiter(store: consumerStore)
            .wait(for: \.ints, running: { _ in
                repoStore.run(.set(\.ints, to: [10, 20]))
            })
            .expect(\.ints, toEqual: [10, 20])
        
        try await StoreWaiter(store: consumerStore)
            .wait(for: \.strings, running: { _ in
                repoStore.run(.set(\.strings, to: ["X", "Y", "Z"]))
            })
            .expect(\.strings, toEqual: ["X", "Y", "Z"])
    }
    
    @MainActor
    @Test("Bind - Chain effects from repository")
    func bindChainEffects() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [1]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        // Create a consumer store
        let consumerStore = TestStore()
        
        // Bind with effect chaining
        consumerStore.bind(
            TestStoreRepositoryKey.self,
            to: \.ints,
            map: { ints in
                .concatenate([
                    .set(\.ints, to: ints),
                    .set(\.strings, to: ints.map { "Value: \($0)" })
                ])
            }
        )
        
        // Wait for binding to establish
        try await Task.sleep(for: .milliseconds(50))
        
        // Update repository
        try await StoreWaiter(store: consumerStore)
            .wait(for: \.ints, count: 1, running: { _ in
                repoStore.run(.set(\.ints, to: [100, 200]))
            })
        
        // Wait for concatenated effects to complete
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(consumerStore.state.ints == [100, 200])
        #expect(consumerStore.state.strings == ["Value: 100", "Value: 200"])
    }
    
    @MainActor
    @Test("Bind - Consumer deinit cleans up binding")
    func bindCleanupOnDeinit() async throws {
        // Set up repository store
        let repoStore = TestStore(state: TestState(ints: [1]))
        AsyncStoreRepository.shared.testStore = repoStore
        
        weak var weakConsumer: TestStore?
        
        autoreleasepool {
            let consumerStore = TestStore()
            weakConsumer = consumerStore
            
            // Bind consumer to repository
            consumerStore.bind(
                TestStoreRepositoryKey.self,
                to: \.ints,
                map: { .set(\.ints, to: $0) }
            )
            
            #expect(weakConsumer != nil)
        }
        
        // Allow time for cleanup
        try await Task.sleep(for: .milliseconds(100))
        
        // Consumer should be deallocated
        try #require(weakConsumer == nil, "Consumer should be deallocated after autoreleasepool")
    }
}
