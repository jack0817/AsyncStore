//
//  AsyncDistributor.swift
//  
//
//  Created by Wendell Thompson on 3/15/22.
//

import Foundation
import SwiftUI

public actor AsyncDistributor<Element> {
    public typealias BufferingPolicy = AsyncStream<Element>.Continuation.BufferingPolicy
    
    private var downstreams: [AnyHashable: AsyncStream<Element>.Continuation] = [:]
    
    public init() {}
    
    public func yield(_ element: Element) {
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
    
    public func stream(
        for id: AnyHashable,
        initialValue: Element,
        _ bufferingPolicy: BufferingPolicy = .unbounded
    ) -> AsyncStream<Element> {
        .init(bufferingPolicy: bufferingPolicy) { cont in
            downstreams[id] = cont
            cont.yield(initialValue)
        }
    }
    
    public func finish(_ id: AnyHashable) {
        guard let cont = downstreams[id] else { return }
        cont.finish()
        downstreams[id] = .none
    }
}
