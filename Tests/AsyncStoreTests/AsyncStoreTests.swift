import Testing
import SwiftSyntax
import SwiftSyntaxMacroExpansion
@testable import AsyncStore

extension Tag {
    @Tag static var effects: Self
}

@MainActor
@Suite("AsyncStore")
struct AsyncStoreTests {
    @MainActor
    @Test("Init")
    func testInit() async throws {
        let expectedState = TestState(integer: 10, string: "Hello", intArray: [3])
        let testStore = TestStore(state: expectedState)
        
        #expect(expectedState.integer == testStore.integer, "")
        #expect(expectedState.string == testStore.string, "")
        #expect(expectedState.intArray == testStore.intArray, "")
    }
}

@MainActor
@Suite("AsyncStore Effects")
struct AsyncStoreEffectTests {
    @Test("None Effect", .tags(.effects))
    func testNoneEffect() async throws {
        let testStore = TestStore()
        let awaiter = StoreAwaiter(store: testStore)
        do {
            try await awaiter.wait(for: \.integer, running: .none, timeout: 1.0)
            #expect(Bool(false), "The store did not time out")
        } catch let error as StoreAwaiter<TestState, TestTaskIdentifier>.Error {
            #expect(error == .timedout)
        } catch {
            #expect(Bool(false), "The store did not time out")
        }
    }
    
    @Test("Set Effect", .tags(.effects))
    func testSetEffect() async throws {
        let expectedState = TestState(
            integer: 10,
            string: "Hello",
            intArray: [3]
        )
        
        let testStore = TestStore()
        let awaiter = StoreAwaiter(store: testStore)
        
        try await awaiter.wait(
            for: \.integer,
            running: .set(\.integer, to: expectedState.integer)
        )
        
        try await awaiter.wait(
            for: \.integer,
            running: .set(\.string, to: expectedState.string)
        )
        
        try await awaiter.wait(
            for: \.intArray,
            running: .set(\.intArray, to: expectedState.intArray)
        )
        
        #expect(testStore.integer == expectedState.integer, "")
        #expect(testStore.string == expectedState.string, "")
        #expect(testStore.intArray == expectedState.intArray, "")
    }
    
    @Test("Concatenate Effect", .tags(.effects))
    func testConcatenateEffect() async throws {
        let expectedResult = [1, 2, 3]
        
        let task1: @Sendable () async throws -> TestStore.Effect = {
            try? await Task.sleep(for: .milliseconds(200))
            return .append(expectedResult[0], to: \.intArray)
        }
        
        let task2: @Sendable () async throws -> TestStore.Effect = {
            try? await Task.sleep(for: .milliseconds(100))
            return .append(expectedResult[1], to: \.intArray)
        }
        
        let task3: @Sendable () async throws -> TestStore.Effect = {
            try? await Task.sleep(for: .milliseconds(0))
            return .append(expectedResult[2], to: \.intArray)
        }
        
        let testStore = TestStore()
        let awaiter = StoreAwaiter(store: testStore)
        try await awaiter.wait(
            for: \.intArray,
            count: 3,
            running: .concatenate(
                .task(task1),
                .task(task2),
                .task(task3)
            )
        )
        
        #expect(testStore.intArray == expectedResult, "")
    }
    
    @Test("Merge Effect", .tags(.effects))
    func testMergeEffect() async throws {
        let expectedResult = [3, 2, 1]
        
        let task1: @Sendable () async throws -> TestStore.Effect = {
            try? await Task.sleep(for: .milliseconds(200))
            return .append(1, to: \.intArray)
        }
        
        let task2: @Sendable () async throws -> TestStore.Effect = {
            try? await Task.sleep(for: .milliseconds(100))
            return .append(2, to: \.intArray)
        }
        
        let task3: @Sendable () async throws -> TestStore.Effect = {
            try? await Task.sleep(for: .milliseconds(0))
            return .append(3, to: \.intArray)
        }
        
        let testStore = TestStore()
        let awaiter = StoreAwaiter(store: testStore)
        try await awaiter.wait(
            for: \.intArray,
            count: 3,
            running: .merge(
                .task(task1),
                .task(task2),
                .task(task3)
            )
        )
        
        #expect(testStore.intArray == expectedResult, "")
    }
}
