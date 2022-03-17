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
        let expectedNextValue = "Next"
        let task1Id = "Task1"
        let task2Id = "Task2"
        let task3Id = "Task3"
        let distributor = AsyncDistributor<String>()
        let stream1 = await distributor.stream(for: task1Id, initialValue: "", .bufferingNewest(1))
        let stream2 = await distributor.stream(for: task2Id, initialValue: "", .bufferingNewest(1))
        let stream3 = await distributor.stream(for: task3Id, initialValue: "", .bufferingNewest(1))
        
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
        
        let task3 = Task<String, Never> {
            var text = ""
            for await element in stream3 {
                text = element
            }
            return text
        }
        
        await distributor.yield(expectedValue)
        await distributor.finish(task1Id)
        await distributor.finish(task2Id)
        
        await distributor.yield(expectedNextValue)
        await distributor.finish(task3Id)
        
        let actualValue1 = await task1.value
        let actualValue2 = await task2.value
        let actualValue3 = await task3.value
        
        XCTAssertEqual(actualValue1, expectedValue)
        XCTAssertEqual(actualValue2, expectedValue)
        XCTAssertEqual(actualValue3, expectedNextValue)
    }
}
