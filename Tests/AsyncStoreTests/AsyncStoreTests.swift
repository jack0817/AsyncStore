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
    
    func testSetEffect() async throws {
        let store = AsyncStore(
            state: TestState(),
            env: TestEnvironment(),
            mapError: { _ in .none }
        )
        
        let waiter = StoreWaiter(store: store)
        
        let expectedValue = "New Value"
        store.receive(.set { $0.value = expectedValue })
        
        await waiter.waitForObjectWillChange(count: 1, timeout: 5.0)
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
        
        let waiter = StoreWaiter(store: store)
        
        store.receive(.task(operation))
        
        await waiter.waitForObjectWillChange(count: 1, timeout: 5.0)
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
        
        let waiter = StoreWaiter(store: store)
        
        store.receive(
            .merge(
                .task(operation1),
                .task(operation2)
            )
        )
        
        await waiter.waitForObjectWillChange(count: 2, timeout: 5.0)
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
        
        let waiter = StoreWaiter(store: store)
        
        store.receive(
            .concatenate(
                .task(operation1),
                .task(operation2)
            )
        )
        
        await waiter.waitForObjectWillChange(count: 2, timeout: 5.0)
        XCTAssertEqual(store.ints, expectedInts)
    }
    
    func testCancelEffect() async  {
        let expectedInts = [2]
        let dataOperation: (Int) async throws -> TestStore.Effect = { value in
            try await Task.trySleep(for: 0.1)
            return .set { $0.ints.append(value) }
        }
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let waiter = StoreWaiter(store: store)
        
        let taskId = "CancelledTask"
        
        store.receive(
            .merge(
                .dataTask(1, dataOperation, taskId),
                .dataTask(2, dataOperation, taskId)
            )
        )
        
        await waiter.waitForObjectWillChange(count: 1, timeout: 5.0)
        XCTAssertEqual(store.ints, expectedInts)
    }
}
