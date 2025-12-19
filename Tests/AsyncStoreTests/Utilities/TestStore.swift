//
//  TestStore.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/18/25.
//

import AsyncStore
import Foundation

struct TestState: Sendable {
    var integer = 0
    var string = ""
    var intArray: [Int] = []
}

enum TestTaskIdentifier: Hashable, Sendable {
    case one
}

typealias TestStore = AsyncStore<TestState, TestTaskIdentifier>

extension TestStore {
    convenience init() {
        self.init(state: .init())
    }
}
