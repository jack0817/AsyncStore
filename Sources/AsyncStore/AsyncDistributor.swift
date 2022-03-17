//
//  AsyncDistributor.swift
//  
//
//  Created by Wendell Thompson on 3/15/22.
//

import Foundation
import SwiftUI

actor AsyncDistributor<Element> {
    typealias BufferingPolicy = AsyncStream<Element>.Continuation.BufferingPolicy
    
    var downstreams: [AnyHashable: AsyncStream<Element>.Continuation] = [:]
    
    func yield(_ element: Element) {
        var terminatedIds: [AnyHashable] = []
        downstreams.forEach { (id, cont) in
            switch cont.yield(element) {
            case .terminated:
                terminatedIds.append(id)
            default:
                break
            }
        }
        terminatedIds.forEach { downstreams[$0] = .none }
    }
    
    func stream(
        for id: AnyHashable,
        initialValue: Element,
        _ bufferingPolicy: BufferingPolicy = .unbounded
    ) -> AsyncStream<Element> {
        .init(bufferingPolicy: bufferingPolicy) { cont in
            downstreams[id] = cont
            cont.yield(initialValue)
        }
    }
    
    func finish(_ id: AnyHashable) {
        guard let cont = downstreams[id] else { return }
        cont.finish()
        downstreams[id] = .none
    }
}
