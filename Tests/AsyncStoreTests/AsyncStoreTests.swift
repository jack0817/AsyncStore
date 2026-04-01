import Testing
@testable import AsyncStore

extension Tag {
    @Tag static var store: Self
    @Tag static var effects: Self
    @Tag static var environment: Self
}

@Suite("Async Store Tests")
struct AsyncStoreTests {
    @MainActor
    @Test("Init", .tags(.store))
    func testInit() async throws {
        let expectedValue = TestState(
            ints: [1, 2, 3],
            strings: ["One", "Two", "Three"],
            error: .test
        )
        
        let testStore = TestStore(state: expectedValue)
        #expect(testStore.state == expectedValue)
    }
    
    @MainActor
    @Test("Set Effect", .tags(.effects))
    func testSetEffect() async throws {
        let expectedValue = [1, 2, 3]
        try await StoreWaiter(store: TestStore())
            .wait(for: \.ints, running: .set(\.ints, to: expectedValue))
            .expect(\.ints, toEqual: expectedValue)
    }
    
    @MainActor
    @Test("Task Effect", .tags(.effects))
    func testTaskEffect() async throws {
        let counter = Counter()
        let task: @Sendable () async throws -> TestStore.Effect = {
            await counter.increment()
            return .set(\.ints, to: [1])
        }
        
        try await StoreWaiter(store: TestStore())
            .wait(for: \.ints, running: .task(task, id: .one))
        
        let count = await counter.count
        #expect(count == 1)
    }
    
    @MainActor
    @Test("Concatenate Effect", .tags(.effects))
    func testConcatenateEffect() async throws {
        @Sendable
        func append(_ int: Int, after duration: Duration) async throws -> TestStore.Effect {
            try await Task.sleep(for: duration)
            return .append(int, to: \.ints)
        }
        
        let concatEffect: TestStore.Effect = .concatenate(
            .task { try await append(1, after: .milliseconds(500)) },
            .task { try await append(2, after: .milliseconds(250)) },
            .task { try await append(3, after: .milliseconds(0)) },
        )
        
        try await StoreWaiter(store: TestStore())
            .wait(for: \.ints, count: 3, running: concatEffect)
            .expect(\.ints, toEqual: [1, 2, 3])
    }
    
    @MainActor
    @Test("Merge Effect", .tags(.effects))
    func testMergeEffect() async throws {
        @Sendable
        func append(_ int: Int, after duration: Duration) async throws -> TestStore.Effect {
            try await Task.sleep(for: duration)
            return .append(int, to: \.ints)
        }
        
        let mergeEffect: TestStore.Effect = .merge(
            .task { try await append(1, after: .milliseconds(500)) },
            .task { try await append(2, after: .milliseconds(250)) },
            .task { try await append(3, after: .milliseconds(0)) },
        )
        
        try await StoreWaiter(store: TestStore())
            .wait(for: \.ints, count: 3, running: mergeEffect)
            .expect(\.ints, toEqual: [3, 2, 1])
    }
    
    @MainActor
    @Test("Environment", .tags(.environment))
    func testEnvironment() async throws {
        let parentEnv = AsyncStoreEnvironmentValues()
        parentEnv.testService = .mock([1, 2, 3])
        
        // Test Environment
        let store1 = TestStore(environment: parentEnv)
        let actualValue1 = try await store1.env.testService.getInts()
        #expect(actualValue1 == [1, 2, 3])
        
        // Test Child Environment
        let store2 = TestStore(environment: store1.env.child())
        let actualValue2 = try await store2.env.testService.getInts()
        #expect(actualValue2 == [1, 2, 3])
        
        // Test Child Override
        store2.env.testService = .mock([3, 2, 1])
        let actualValue3 = try await store2.env.testService.getInts()
        #expect(actualValue3 == [3, 2, 1])
        
    }
}
