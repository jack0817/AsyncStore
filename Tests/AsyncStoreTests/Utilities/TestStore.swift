//
//  TestStore.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/18/25.
//

import AsyncStore
import Foundation

struct TestState: Sendable {
    enum Error: Swift.Error, Equatable {
        case cancelled(String)
        case other(String)
        
        var isCancelled: Bool {
            switch self {
            case .cancelled: true
            default: false
            }
        }
    }
    
    var integer = 0
    var string = ""
    var intArray: [Int] = []
    var error: Error? = .none
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
