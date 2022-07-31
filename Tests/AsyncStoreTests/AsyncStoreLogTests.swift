//
//  AsyncStoreLogTests.swift
//  
//
//  Created by Wendell Thompson on 7/31/22.
//

import Foundation
import XCTest
@testable import AsyncStore

final class AsyncStoreLogTests: XCTestCase {
    enum TestError: Error {
        case message(String)
    }
    
    func testError() {
        var actualMessages: [String] = []
        let expectedMessageCount = 2
        
        AsyncStoreLog.setLevel(.error)
        AsyncStoreLog.setOutput { msg in
            actualMessages.append(msg)
            print(msg)
        }
        
        AsyncStoreLog.error(TestError.message("Error"))
        AsyncStoreLog.error("Error")
        AsyncStoreLog.debug("Debug")
        AsyncStoreLog.warning("Warning")
        AsyncStoreLog.info("Info")
        
        XCTAssertEqual(actualMessages.count, expectedMessageCount)
    }
    
    func testDebug() {
        var actualMessages: [String] = []
        let expectedMessageCount = 3
        
        AsyncStoreLog.setLevel(.debug)
        AsyncStoreLog.setOutput { msg in
            actualMessages.append(msg)
            print(msg)
        }
        
        AsyncStoreLog.error(TestError.message("Error"))
        AsyncStoreLog.error("Error")
        AsyncStoreLog.debug("Debug")
        AsyncStoreLog.warning("Warning")
        AsyncStoreLog.info("Info")
        
        XCTAssertEqual(actualMessages.count, expectedMessageCount)
    }
    
    func testWarning() {
        var actualMessages: [String] = []
        let expectedMessageCount = 4
        
        AsyncStoreLog.setLevel(.warning)
        AsyncStoreLog.setOutput { msg in
            actualMessages.append(msg)
            print(msg)
        }
        
        AsyncStoreLog.error(TestError.message("Error"))
        AsyncStoreLog.error("Error")
        AsyncStoreLog.debug("Debug")
        AsyncStoreLog.warning("Warning")
        AsyncStoreLog.info("Info")
        
        XCTAssertEqual(actualMessages.count, expectedMessageCount)
    }
    
    func testInfo() {
        var actualMessages: [String] = []
        let expectedMessageCount = 5
        
        AsyncStoreLog.setLevel(.info)
        AsyncStoreLog.setOutput { msg in
            actualMessages.append(msg)
            print(msg)
        }
        
        AsyncStoreLog.error(TestError.message("Error"))
        AsyncStoreLog.error("Error")
        AsyncStoreLog.debug("Debug")
        AsyncStoreLog.warning("Warning")
        AsyncStoreLog.info("Info")
        
        XCTAssertEqual(actualMessages.count, expectedMessageCount)
    }
}
