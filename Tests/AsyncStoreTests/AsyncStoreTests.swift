import XCTest
import Combine
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
    
    final class StoreObserver {
        static func waitForObjectWillChange<State, Env>(on store: AsyncStore<State, Env>) async {
            var cancellable: AnyCancellable? = .none
            await withCheckedContinuation { cont in
                cancellable = store.objectWillChange
                    .sink { _ in
                        cont.resume()
                    }
            }
            cancellable?.cancel()
            cancellable = .none
        }
    }
    
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
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(store.state, expectedState)
        XCTAssertEqual(store.env, expectedEnvironment)
    }
    
    func testSetEffect() async {
        let store = AsyncStore(
            state: TestState(),
            env: TestEnvironment(),
            mapError: { _ in .none }
        )
        
        let expectedValue = "New Value"
        store.receive(.set { $0.value = expectedValue })
        
        await StoreObserver.waitForObjectWillChange(on: store)
        XCTAssertEqual(store.value, expectedValue)
    }
    
    func testTaskEffect() async {
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
        
        store.receive(.task(operation))
        
        await StoreObserver.waitForObjectWillChange(on: store)
        XCTAssertEqual(count, expectedCount)
        XCTAssertEqual(store.value, expectedValue)
    }
    
    func testMergeEffect() {
        let expectedInts = [2, 1]
        let operation1: () async throws -> TestStore.Effect = {
            try? await Task.sleep(nanoseconds: 500_000_000)
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
        
        let expectation = XCTestExpectation(description: #function)
        expectation.expectedFulfillmentCount = 2
        
        var cancellable: AnyCancellable? = .none
        cancellable = store.objectWillChange.sink { _ in
            expectation.fulfill()
        }
        
        store.receive(
            .merge(
                .task(operation1),
                .task(operation2)
            )
        )
        
        wait(for: [expectation], timeout: 5.0)
        cancellable?.cancel()
        
        XCTAssertEqual(store.ints, expectedInts)
    }
    
    func testConcatenateEffect() {
        let expectedInts = [1, 2]
        let operation1: () async throws -> TestStore.Effect = {
            try? await Task.sleep(nanoseconds: 500_000_000)
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
        
        let expectation = XCTestExpectation(description: #function)
        expectation.expectedFulfillmentCount = 2
        
        var cancellable: AnyCancellable? = .none
        cancellable = store.objectWillChange.sink { _ in
            expectation.fulfill()
        }
        
        store.receive(
            .concatenate(
                .task(operation1),
                .task(operation2)
            )
        )
        
        wait(for: [expectation], timeout: 5.0)
        cancellable?.cancel()
        
        XCTAssertEqual(store.ints, expectedInts)
    }
    
    func testCancelEffect()  {
        let operation1: () async throws -> TestStore.Effect = {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return .none
        }
        
        let expectation = XCTestExpectation(description: #function)
        expectation.expectedFulfillmentCount = 2
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { error in
                switch error {
                case is CancellationError:
                    expectation.fulfill()
                default:
                    break
                }
                return .none
            }
        )
        
        let taskId = "CancelledTask"
        
        store.receive(
            .merge(
                .task(operation: operation1, id: taskId),
                .task(operation: operation1, id: taskId),
                .cancel(taskId)
            )
        )
        
        wait(for: [expectation], timeout: 5.0)
    }
}
