import Testing
import SwiftSyntax
import SwiftSyntaxMacroExpansion
@testable import AsyncStore

extension Tag {
    @Tag static var effects: Self
}

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

@Suite("AsyncStore Effects")
struct AsyncStoreEffectTests {
    @MainActor
    @Test("Set Effect", .tags(.effects))
    func testSetEffectInit() async throws {
        let expectedState = TestState(integer: 10, string: "Hello", intArray: [3])
        let testStore = TestStore(state: expectedState)
        testStore.run(.set(\.integer, to: 10))
        
        #expect(expectedState.integer == testStore.integer, "")
        #expect(expectedState.string == testStore.string, "")
        #expect(expectedState.intArray == testStore.intArray, "")
    }
}
