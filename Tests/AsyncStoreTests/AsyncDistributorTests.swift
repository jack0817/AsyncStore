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
    override class func tearDown() {
        AsyncStoreLog.setOutput { _ in }
    }
    
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
    
//    func testOverrideLogging() async {
//        let overrideId = "Test"
//        var actualLogs: [String] = []
//
//        let expectation = expectation(description: "testOverrideLogging")
//        expectation.expectedFulfillmentCount = 1
//
//        AsyncStoreLog.setLevel(.info)
//        AsyncStoreLog.setOutput { message in
//            actualLogs.append(message)
//            print(message)
//            expectation.fulfill()
//        }
//
//        let distributor = AsyncDistributor<String>()
//        _ = distributor.stream(for: overrideId, initialValue: "Test 1", bufferingPolicy: .unbounded)
//        _ = distributor.stream(for: overrideId, initialValue: "Test 2", bufferingPolicy: .unbounded)
//
//        await waitForExpectations(timeout: 5.0)
//        XCTAssertEqual(actualLogs.count, 1)
//    }
}
