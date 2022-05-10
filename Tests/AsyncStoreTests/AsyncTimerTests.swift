//
//  AsyncTimerTests.swift
//  
//
//  Created by Wendell Thompson on 5/10/22.
//

import XCTest
@testable import AsyncStore

final class AsyncTimerTests: XCTestCase {
    func testAccuracy() async {
        let intervalNano: Int64 = 250_000_000
        let timer = AsyncStore<String, String>.AsyncTimer(interval: Double(intervalNano) * 0.000_000_001)
        let accuracyRange: ClosedRange<UInt64> =
            UInt64(Double(abs(intervalNano)) * 0.9) ... UInt64(Double(abs(intervalNano)) * 1.1)
        
        var elapsedTimes: [UInt64] = []
        let maxCount = 8
        var currentCount = 0
        let startTime = DispatchTime.now().uptimeNanoseconds
        var previousTime = startTime
        
        for await _ in timer {
            let endTime = DispatchTime.now().uptimeNanoseconds
            let elapsedTime = endTime - previousTime
            elapsedTimes.append(elapsedTime)
            previousTime = endTime
            currentCount += 1
            guard currentCount < maxCount else { break }
        }
        
        print("[AsyncTimerTests] range:\(accuracyRange)")
        elapsedTimes.forEach { elapsedTime in
            XCTAssertTrue(
                accuracyRange.contains(elapsedTime),
                "Value \(elapsedTime) is outside the range \(accuracyRange)"
            )
        }
    }
}
