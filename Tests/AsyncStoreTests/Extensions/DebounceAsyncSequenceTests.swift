//
//  File.swift
//  
//
//  Created by Wendell Thompson on 10/5/22.
//

import Foundation
import XCTest
@testable import AsyncStore

final class DebounceAsyncSequenceTests: XCTestCase {
    struct CountState: Equatable {
        var count = 0
        var value = ""
    }
    
    func testDebounceStream() async {
        let sourceStore = AsyncStore<String, String>(
            state: "",
            env: "",
            mapError: { _ in .none }
        )
        
        let countStore = AsyncStore<CountState, String>.init(
            state: .init(),
            env: "",
            mapError: { _ in .none }
        )
        
        countStore.bind(
            id: "CountStore.SourceStore",
            to: sourceStore
                .stream(for: "CountStore.SourceStore.Stream", at: \.self)
                .debounce(for: 0.25),
            mapEffect: { value in
                return .set { state in
                    state.value = value
                    state.count += 1
                }
            }
        )
        
        let thrashRange = 0 ... 100
        
        let sourceWaiter = StoreWaiter(store: sourceStore, count: thrashRange.upperBound)
        let countWaiter = StoreWaiter(store: countStore, count: 1)
        
        
        for thrash in thrashRange {
            sourceStore.receive(.set(\.self, to: "\(thrash)"))
        }
        
        await sourceWaiter.wait(timeout: 5.0)
        await countWaiter.wait(timeout: 5.0)
        countStore.receive(.cancel("CountStore.SourceStore"))
        
        XCTAssertEqual(sourceStore.state, "\(thrashRange.upperBound)")
        XCTAssertEqual(countStore.count, 1)
        XCTAssertEqual(countStore.value, "\(thrashRange.upperBound)")
    }
}
