//
//  AsyncTimerTests.swift
//
//
//  Created by Wendell Thompson on 3/17/22.
//

import XCTest
@testable import AsyncStore

final class AsyncStoreTests: XCTestCase {
    struct TestState: Equatable {
        var value = ""
        var ints: [Int] = []
        var dates: [Date] = []
        var isCompleted = false
    }
    
    struct TestEnvironment: Equatable {
        var value = ""
    }
    
    typealias TestStore = AsyncStore<TestState, TestEnvironment>
    
    override func setUp() async throws {
        AsyncStoreLog.setOutput { logMessage in
            print(logMessage)
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
        
        let expectedValue = "New Value"
        let condition = StoreCondition(store: store, condition: { $0.value == expectedValue })
        
        store.receive(.set { $0.value = expectedValue })
        
        await condition.wait(for: 5.0)
        
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
        
        let condition = StoreCondition(store: store, condition: \.isCompleted)
        
        store.receive(
            .concatenate(
                .task(operation),
                .set(\.isCompleted, to: true)
            )
        )
        
        await condition.wait(for: 5.0)
        XCTAssertEqual(count, expectedCount)
        XCTAssertEqual(store.value, expectedValue)
    }
    
    func testDebounceEffect() async throws {
        var cancelCount = 0
        let thrashCount = 10
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { error in
                switch error {
                case is CancellationError:
                    cancelCount += 1
                    return .none
                default:
                    return .none
                }
            }
        )
        
        let condition = StoreCondition(store, \.ints.count, equals: 1)
        
        for i in 0 ..< thrashCount {
            store.receive(
                .debounce(
                    operation: { .append(i, to: \.ints) },
                    id: "Thrash",
                    delay: 0.5
                )
            )
        }
        
        await condition.wait(for: 5.0)
        
        XCTAssertEqual(cancelCount, thrashCount - 1)
        XCTAssertEqual(store.ints.count, 1)
        XCTAssertEqual(store.ints[0], thrashCount - 1)
    }
    
    func testDebounceWarning() async throws {
        var actualMessages: [String] = []
        let expectedMessage = "Concatenated debounce effects may not be debounced as they will be synchronized."
        
        AsyncStoreLog.setLevel(.warning)
        AsyncStoreLog.setOutput { log in
            actualMessages.append(log)
            print(log)
        }
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in .none }
        )
        
        let condition = StoreCondition(store, \.ints.count, equals: 1)
        
        store.receive(
            .concatenate(
                .debounce(
                    operation: { .append(0, to: \.ints) },
                    id: "Thrash",
                    delay: 0.5
                )
            )
        )
        
        await condition.wait(for: 5.0)
        
        XCTAssertTrue(actualMessages.contains(where: { $0.contains(expectedMessage) }))
    }
    
    func testDebounceDataEffect() async throws {
        var cancelCount = 0
        let thrashCount = 10
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { error in
                switch error {
                case is CancellationError:
                    cancelCount += 1
                    return .none
                default:
                    return .none
                }
            }
        )
        
        let condition = StoreCondition(store, \.ints.count, equals: 1)
        
        for i in 0 ..< thrashCount {
            store.receive(
                .debounce(
                    operation: { .append(i, to: \.ints) },
                    id: "Thrash",
                    delay: 0.5
                )
            )
        }
        
        await condition.wait(for: 5.0)
        
        XCTAssertEqual(cancelCount, thrashCount - 1)
        XCTAssertEqual(store.ints.count, 1)
        XCTAssertEqual(store.ints[0], thrashCount - 1)
    }
    
    func testTimerEffect() async throws {
        let expectedDatesCount = 3
        let expectedValue = "TimerStarted"
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in .none }
        )
        
        let condition = StoreCondition(store, \.dates.count, equals: 3)
        
        store.receive(
            .concatenate(
                .timer(
                    0.1,
                    id: "Timer",
                    mapEffect: { tick in
                        .set { $0.dates.append(tick) }
                    }
                ),
                .set(\.value, to: expectedValue)
            )
        )
        
        await condition.wait(for: 5.0)
        store.receive(.cancel("Timer"))
        try? await Task.trySleep(for: 0.25)
        
        XCTAssertEqual(store.dates.count, expectedDatesCount)
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
        
        let condition = StoreCondition(store, \.ints.count, equals: 2)
        
        store.receive(
            .merge(
                .task(operation1),
                .task(operation2)
            )
        )
        
        await condition.wait(for: 5.0)
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
        
        let condition = StoreCondition(store, \.ints.count, equals: 2)
        
        store.receive(
            .concatenate(
                .task(operation1),
                .task(operation2)
            )
        )
        
        await condition.wait(for: 5.0)
        XCTAssertEqual(store.ints, expectedInts)
    }
    
    func testCancelEffect() async  {
        let expectedInts = [2]
        let taskId = "CancelledTask"
        var cancelError: Error? = .none
        
        let dataOperation: (Int) async throws -> TestStore.Effect = { value in
            try await Task.trySleep(for: 0.25)
            return .set { $0.ints.append(value) }
        }

        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { error in
                cancelError = error
                return .none
            }
        )

        let condition = StoreCondition(store, \.ints.count, equals: 1)

        store.receive(.dataTask(1, dataOperation, taskId))
        try? await Task.trySleep(for: 0.1)
        store.receive(.dataTask(2, dataOperation, taskId))

        await condition.wait(for: 5.0)
        
        XCTAssertEqual(store.ints, expectedInts)
        XCTAssertNotNil(cancelError)
        XCTAssertTrue(cancelError is CancellationError)
    }
    
    func testBindToKeyPath() async {
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let condition = StoreCondition(store: store, condition: { !$0.value.isEmpty })
        
        store.bind(
            id: "asyncBind",
            to: \.ints,
            mapEffect: { ints in
                return .set{ $0.value = ints.map(String.init).joined() }
            }
        )
        
        store.receive(.set({ $0.ints = [1, 2] }))
        await condition.wait(for: 5.0)
        XCTAssertEqual(store.value, "12")
    }
    
    func testBindToStream() async {
        let expectedDate1 = Date()
        let expectedDate2 = Calendar.current.date(byAdding: .day, value: 1, to: expectedDate1)!
        let expectedDate3 = Calendar.current.date(byAdding: .day, value: 1, to: expectedDate2)!
        
        var continuation: AsyncStream<Date>.Continuation! = .none
        let stream = AsyncStream<Date> { cont in
            continuation = cont
        }
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let condition = StoreCondition(store, \.dates.count, equals: 2)
        
        store.bind(
            id: "Stream",
            to: stream,
            mapEffect: { date in
                .set { state in
                    state.dates.append(date)
                }
            }
        )
        
        continuation.yield(expectedDate1)
        continuation.yield(expectedDate2)
        await condition.wait(for: 5.0)
        
        store.receive(.cancel("Stream"))
        try? await Task.trySleep(for: 0.5)
        
        continuation.yield(expectedDate3)
        continuation.finish()
        
        XCTAssertEqual(store.dates.count, 2)
        XCTAssertEqual(store.dates.first, expectedDate1)
        XCTAssertEqual(store.dates.last, expectedDate2)
        XCTAssertTrue(!store.dates.contains(expectedDate3))
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
        
        store.bind(
            id: "asyncBind",
            to: parentStore,
            on: \.value,
            mapEffect: { parentValue in .set { $0.value = parentValue } }
        )
        
        let condition = StoreCondition(store: store, condition: { !$0.value.isEmpty })
        parentStore.receive(.set({ $0.value = exptectedValue }))
        await condition.wait(for: 5.0)
        XCTAssertEqual(store.value, exptectedValue)
    }
    
    func testReceiveOffMainThread() async {
        var actualMessages: [String] = []
        let expectedMessage = "'receive' should only be called from the main thread"
        
        AsyncStoreLog.setLevel(.warning)
        AsyncStoreLog.setOutput {
            actualMessages.append($0)
            print($0)
        }
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let expectation = expectation(description: "testReceiveOffMainThread")
        expectation.expectedFulfillmentCount = 1
        
        DispatchQueue.global(qos: .background).async {
            store.receive(.none)
            expectation.fulfill()
        }
        
        await waitForExpectations(timeout: 5.0)
        
        XCTAssertTrue(actualMessages.contains(where: { $0.contains(expectedMessage) }))
    }
    
    func testReceiveOnMainThread() async {
        var actualMessages: [String] = []
        let expectedMessage = "'receive' should only be called on from the main thread"
        
        AsyncStoreLog.setLevel(.warning)
        AsyncStoreLog.setOutput {
            actualMessages.append($0)
            print($0)
        }
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let expectation = expectation(description: "testReceiveOffMainThread")
        expectation.expectedFulfillmentCount = 1
        
        DispatchQueue.main.async {
            store.receive(.none)
            expectation.fulfill()
        }
        
        await waitForExpectations(timeout: 5.0)
        
        XCTAssertTrue(!actualMessages.contains(where: { $0.contains(expectedMessage) }))
    }
    
    func testRemoveDuplicates() async {
        struct SourceState: Equatable {
            var value = 0
            var isCompleted = false
        }
        
        let sourceStore = AsyncStore<SourceState, String>(state: .init(), env: "", mapError: { _ in .none })
        let destStore = AsyncStore<Int, String>(state: 0, env: "", mapError: { _ in .none })
        
        var actualValues: [Int] = []
        let expectedValues: [Int] = [0, 1, 2, 3]
        
        destStore.bind(
            id: "DestStore",
            to: sourceStore,
            on: \.value,
            mapEffect: { value in
                actualValues.append(value)
                return .none
            }
        )
        
        sourceStore.receive(
            .concatenate(
                .set(\.value, to: 1),
                .set(\.value, to: 1),
                .set(\.value, to: 2),
                .set(\.value, to: 2),
                .set(\.value, to: 3),
                .set(\.value, to: 3),
                .set(\.isCompleted, to: true)
            )
        )
        
        let storeCondition = StoreCondition(store: sourceStore, condition: \.isCompleted)
        await storeCondition.wait(for: 5.0)
        
        sourceStore.deactivate()
        destStore.deactivate()
        
        XCTAssertEqual(actualValues, expectedValues)
    }
    
    func testDeactivation() async {
        let expectedState = "Unchanged"
        let expectedLog = "deactivated"
        
        let testStore = AsyncStore<String, String>(
            state: expectedState,
            env: "",
            mapError: { _ in .none }
        )
        
        var actualLogs: [String] = []
        AsyncStoreLog.setOutput { log in
            actualLogs.append(log)
        }
        
        testStore.deactivate()
        testStore.receive(.set(\.self, to: "Changed"))
        
        XCTAssertFalse(testStore.isActive)
        XCTAssertTrue(testStore.state == expectedState)
        XCTAssertTrue(actualLogs.count > 0)
        XCTAssertTrue(actualLogs.contains(where: { $0.contains(expectedLog) }))
        
        AsyncStoreLog.setOutput(.none)
    }
}

// MARK: Sequence Effect Tests

extension AsyncStoreTests {
    func testAppend() async {
        let expectedValue = [1]
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let condition = StoreCondition(store, \.ints.count, equals: 1)
        store.receive(.append(expectedValue[0], to: \.ints))
        await condition.wait(for: 5.0)
        XCTAssertEqual(store.ints, expectedValue)
    }
    
    func testInsert() async {
        let expectedValue = [1]
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let condition = StoreCondition(store, \.ints.count, equals: 1)
        store.receive(.insert(expectedValue[0], at: 0, to: \.ints))
        await condition.wait(for: 5.0)
        XCTAssertEqual(store.ints, expectedValue)
    }
    
    func testRemove() async {
        let expectedValue = [1]
        let state = TestState(value: "", ints: [1, 2], dates: [])
        let store = TestStore(
            state: state,
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let condition = StoreCondition(store, \.ints.count, equals: 1)
        store.receive(.remove(at: 1, from: \.ints))
        await condition.wait(for: 5.0)
        XCTAssertEqual(store.ints, expectedValue)
    }
    
    func testRemoveFirst() async {
        let expectedValue = [1]
        let state = TestState(value: "", ints: [2, 1], dates: [])
        let store = TestStore(
            state: state,
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let condition = StoreCondition(store, \.ints.count, equals: 1)
        store.receive(.removeFirst(from: \.ints))
        await condition.wait(for: 5.0)
        XCTAssertEqual(store.ints, expectedValue)
    }
    
    func testRemoveLast() async {
        let expectedValue = [1]
        let state = TestState(value: "", ints: [1, 2], dates: [])
        let store = TestStore(
            state: state,
            env: .init(),
            mapError: { _ in
                return .none
            }
        )
        
        let condition = StoreCondition(store, \.ints.count, equals: 1)
        store.receive(.removeLast(from: \.ints))
        await condition.wait(for: 5.0)
        store.deactivate()
        XCTAssertEqual(store.ints, expectedValue)
    }
}
