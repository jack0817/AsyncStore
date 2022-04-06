//
//  AsyncDistributorTests.swift
//  
//
//  Created by Wendell Thompson on 3/17/22.
//

import Foundation
import XCTest
@testable import AsyncStore

final class AsyncDistributorTests: XCTestCase {
    func testYield() async {
        let expectedValue = "Test"
        let task1Id = "Task1"
        let task2Id = "Task2"
        let distributor = AsyncDistributor<String>()
        let stream1 = distributor.stream(for: task1Id, initialValue: "", bufferingPolicy: .bufferingNewest(1))
        let stream2 = distributor.stream(for: task2Id, initialValue: "", bufferingPolicy: .bufferingNewest(1))
        
        let task1 = Task<String, Never> {
            var text = ""
            for await element in stream1 {
                text = element
            }
            return text
        }
        
        let task2 = Task<String, Never> {
            var text = ""
            for await element in stream2 {
                text = element
            }
            return text
        }
        
        distributor.yield(expectedValue)
        try? await Task.trySleep(for: 0.1)
        
        distributor.finishAll()
        task1.cancel()
        task2.cancel()
        
        let actualValue1 = await task1.value
        let actualValue2 = await task2.value
        
        XCTAssertEqual(actualValue1, expectedValue)
        XCTAssertEqual(actualValue2, expectedValue)
    }
}
