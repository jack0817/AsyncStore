//
//  AsyncDistributor.swift
//  
//
//  Created by Wendell Thompson on 3/15/22.
//

import Foundation

final class AsyncDistributor<Value> {
    private var continuations: [AnyHashable: AsyncStream<Value>.Continuation] = [:]
    
    func stream(
        id: AnyHashable,
        _ bufferingPolicy: AsyncStream<Value>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Value> {
        .init(bufferingPolicy: bufferingPolicy) { cont in
            continuations[id] = cont
        }
    }
    
    func yield(_ value: Value) {
        var terminatedIds: [AnyHashable] = []
        continuations.forEach { (id, cont) in
            let result = cont.yield(value)
            switch result {
            case .terminated:
                terminatedIds.append(id)
            default:
                break
            }
        }
        terminatedIds.forEach { continuations[$0] = .none }
    }
    
    func cancel(id: AnyHashable) {
        guard let cont = continuations[id] else { return }
        cont.finish()
        continuations[id] = .none
    }
}
