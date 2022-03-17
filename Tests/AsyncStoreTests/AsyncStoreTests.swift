import XCTest
@testable import AsyncStore

final class AsyncStoreTests: XCTestCase {
    struct TestState: Equatable {
        var value = ""
        var ints: [Int] = []
    }
    
    struct TestEnvironment: Equatable {
        var value = ""
    }
    
    typealias TestStore = AsyncStore<TestState, TestEnvironment>
    
    func testInit() async {
        let expectedState = TestState(value: #function)
        let expectedEnvironment = TestEnvironment(value: #function)
        
        let store = AsyncStore(
            state: expectedState,
            env: expectedEnvironment,
            mapError: { _ in .none }
        )
        
        XCTAssertEqual(store.state, expectedState)
        XCTAssertEqual(store.env, expectedEnvironment)
    }
    
    func testNoneEffect() async {
        let expectedState = TestState(value: #function)
        let expectedEnvironment = TestEnvironment(value: #function)
        
        let store = AsyncStore(
            state: expectedState,
            env: expectedEnvironment,
            mapError: { _ in .none }
        )
        
        store.receive(.none)
        try? await Task.sleep(nanoseconds: 500_000)
        
        XCTAssertEqual(store.state, expectedState)
        XCTAssertEqual(store.env, expectedEnvironment)
    }
    
    func testSetEffect() async {
        let store = AsyncStore(
            state: TestState(),
            env: TestEnvironment(),
            mapError: { _ in .none }
        )
        
        let waiter = StoreWaiter(store: store, count: 1)
        
        let expectedValue = "New Value"
        store.receive(.set { $0.value = expectedValue })
        
        await waiter.wait(timeout: 5.0)
        
        XCTAssertEqual(store.value, expectedValue)
    }
    
    func testTaskEffect() async throws {
        var count = 0
        let expectedCount = 1
        let expectedValue = "Done"
        let operation: () async throws -> TestStore.Effect = {
            count += 1
            return .set { $0.value = expectedValue }
        }
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in .none }
        )
        
        let waiter = StoreWaiter(store: store, count: 1)
        
        store.receive(.task(operation))
        
        await waiter.wait(timeout: 5.0
        )
        XCTAssertEqual(count, expectedCount)
        XCTAssertEqual(store.value, expectedValue)
    }
    
    func testMergeEffect() async throws {
        let expectedInts = [2, 1]
        
        let operation1: () async throws -> TestStore.Effect = {
            try? await Task.sleep(nanoseconds: 500_000)
            return .set { $0.ints.append(1) }
        }
        
        let operation2: () async throws -> TestStore.Effect = {
            return .set { $0.ints.append(2) }
        }
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in .none }
        )
        
        let waiter = StoreWaiter(store: store, count: 2)
        
        store.receive(
            .merge(
                .task(operation1),
                .task(operation2)
            )
        )
        
        await waiter.wait(timeout: 5.0)
        XCTAssertEqual(store.ints, expectedInts)
    }
    
    func testConcatenateEffect() async throws {
        let expectedInts = [1, 2]
        let operation1: () async throws -> TestStore.Effect = {
            try? await Task.sleep(nanoseconds: 500_000)
            return .set { $0.ints.append(1) }
        }
        
        let operation2: () async throws -> TestStore.Effect = {
            return .set { $0.ints.append(2) }
        }
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in .none }
        )
        
        let waiter = StoreWaiter(store: store, count: 2)
        
        store.receive(
            .concatenate(
                .task(operation1),
                .task(operation2)
            )
        )
        
        await waiter.wait(timeout: 5.0)
        XCTAssertEqual(store.ints, expectedInts)
    }
    
    func testCancelEffect() async  {
        let expectedInts = [2]
        let dataOperation: (Int) async throws -> TestStore.Effect = { value in
            try await Task.trySleep(for: 1.0)
            return .set { $0.ints.append(value) }
        }

        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )

        let waiter = StoreWaiter(store: store, count: 1)

        let taskId = "CancelledTask"

        store.receive(.dataTask(1, dataOperation, taskId))
        store.receive(.dataTask(2, dataOperation, taskId))

        await waiter.wait(timeout: 5.0)
        XCTAssertEqual(store.ints, expectedInts)
    }
    
    func testBindToKeyPath() async {
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        await store.bind(
            id: "asyncBind",
            to: \.ints,
            mapEffect: { ints in
                .set{ $0.value = ints.map(String.init).joined() }
            }
        )
        
        let waiter = StoreWaiter(store: store, count: 2)
        store.receive(.set({ $0.ints = [1, 2] }))
        await waiter.wait(timeout: 5.0)
        XCTAssertEqual(store.value, "12")
    }
    
    func testBindToParentStore() async {
        let exptectedValue = "Parent"
        
        let parentStore = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        await store.bind(
            id: "asyncBind",
            to: parentStore,
            on: \.value,
            mapEffect: { parentValue in .set { $0.value = parentValue } }
        )
        
        let waiter = StoreWaiter(store: store, count: 1)
        parentStore.receive(.set({ $0.value = exptectedValue }))
        await waiter.wait(timeout: 5.0)
        XCTAssertEqual(store.value, exptectedValue)
    }
}

