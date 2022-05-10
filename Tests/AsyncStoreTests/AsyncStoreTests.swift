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
        
        await waiter.wait(timeout: 5.0)
        XCTAssertEqual(count, expectedCount)
        XCTAssertEqual(store.value, expectedValue)
    }
    
    func testTimerEffect() async throws {
        let expectedDatesCount = 2
        let expectedValue = "TimerStarted"
        
        let store = TestStore(
            state: .init(),
            env: .init(),
            mapError: { _ in .none }
        )
        
        let waiter = StoreWaiter(store: store, count: 3)
        
        store.receive(
            .concatenate(
                .timer(
                    0.1,
                    id: "Timer",
                    mapEffect: { tick in
                        return .set { $0.dates.append(tick) }
                    }
                ),
                .set(\.value, to: expectedValue)
            )
        )
        
        await waiter.wait(timeout: 5.0)
        store.receive(.cancel("Timer"))
        try? await Task.trySleep(for: 0.25)
        
        let actualDatesCount = store.dates.count
        XCTAssertEqual(actualDatesCount, expectedDatesCount)
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
        let taskId = "CancelledTask"
        var cancelError: Error? = .none
        
        let dataOperation: (Int) async throws -> TestStore.Effect = { value in
            try await Task.trySleep(for: 0.5)
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

        let waiter = StoreWaiter(store: store, count: 1)

        store.receive(.dataTask(1, dataOperation, taskId))
        try? await Task.trySleep(for: 0.1)
        store.receive(.dataTask(2, dataOperation, taskId))

        await waiter.wait(timeout: 5.0)
        
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
        
        let waiter = StoreWaiter(store: store, count: 3)
        
        store.bind(
            id: "asyncBind",
            to: \.ints,
            mapEffect: { ints in
                return .set{ $0.value = ints.map(String.init).joined() }
            }
        )
        
        store.receive(.set({ $0.ints = [1, 2] }))
        await waiter.wait(timeout: 5.0)
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
        
        let waiter = StoreWaiter(store: store, count: 2)
        
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
        await waiter.wait(timeout: 5.0)
        
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
        
        let waiter = StoreWaiter(store: store, count: 2)
        parentStore.receive(.set({ $0.value = exptectedValue }))
        await waiter.wait(timeout: 5.0)
        XCTAssertEqual(store.value, exptectedValue)
    }
}

