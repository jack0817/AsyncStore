//
//  AsyncDistributor.swift
//  
//
//  Created by Wendell Thompson on 3/15/22.
//

import Foundation
import SwiftUI

public struct AsyncDistributor<Element> {
    public typealias BufferingPolicy = AsyncStream<Element>.Continuation.BufferingPolicy
    
    private let continuations = AsyncAtomicStore<AsyncStream<Element>.Continuation>()
    
    private var logTag: String {
        "[\(type(of: self))]"
    }
    
    public init() {}
    
    public func count() async -> Int {
        return continuations.count()
    }
    
    public func stream(
        for id: AnyHashable,
        initialValue: Element,
        bufferingPolicy: BufferingPolicy
    ) -> AsyncStream<Element> {
        if continuations.get(id: id) != nil {
            AsyncStoreLog.info("\(logTag) overriding stream '\(id)'")
        }
        
        return .init(bufferingPolicy: bufferingPolicy) { cont in
            continuations.set(id: id, to: cont)
            cont.yield(initialValue)
        }
    }
    
    public func yield(_ element: Element) {
        var terminatedIds: [AnyHashable] = []
        let ids = continuations.keys()

        for id in ids {
            if let continuation = continuations.get(id: id) {
                switch continuation.yield(element) {
                case .terminated:
                    terminatedIds.append(id)
                    AsyncStoreLog.warning("\(logTag) yield to terminated stream, id:\"\(id)\"")
                case .dropped(let element):
                    AsyncStoreLog.warning("\(logTag) dropped \(type(of: element))  id:\"\(id)\"")
                default:
                    break
                }
            }
        }
        
        terminatedIds.forEach { continuations.set(id: $0, to: .none) }
    }
    
    public func finish(_ id: AnyHashable) {
        continuations.get(id: id)?.finish()
        continuations.set(id: id, to: .none)
    }
    
    public func finishAll() {
        let ids = continuations.keys()
        ids.forEach { finish($0) }
    }
}
