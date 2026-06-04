//
//  Counter.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 4/1/26.
//

import Foundation

public final actor Counter: Sendable {
    public fileprivate(set) var count = 0
    
    func increment() {
        count += 1
    }
}
