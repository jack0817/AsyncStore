//
//  AsyncStoreMacroTests.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/18/25.
//

import Testing
@testable import AsyncStore

struct Test {
    @Test("Test Stringify")
    func test() async throws {
        let expectedValue = "123"
        let actualValue = #Stringify(123)
        #expect(actualValue == expectedValue, "[Stringify] failed to generate the correct value")
    }
}
