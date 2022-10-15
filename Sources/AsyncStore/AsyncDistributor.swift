//
//  AsyncDistributor.swift
//  
//
//  Created by Wendell Thompson on 3/15/22.
//

import Foundation
import SwiftUI

public struct AsyncDistributor<Element> {
    fileprivate actor ContinuationActor {
        var count: Int {
            continuations.count
        }
        
        private var continuations: [AnyHashable: AsyncStream<Element>.Continuation] = [:]
        
        private var logTag: String {
            "[AsyncDistributor<\(Element.self)>]"
        }
        
        func add(_ stream: AsyncStream<Element>.Continuation, for id: AnyHashable) {
            switch continuations[id] {
            case .some:
                AsyncStoreLog.info("\(logTag) overriding stream id \"\(id)\"")
                finish(id)
            default:
                break
            }
            continuations[id] = stream
        }
        
        func yield(_ element: Element) {
            guard count > 0 else {
                AsyncStoreLog.info("\(logTag) yield to no downstreams, \(type(of: element))")
                return
            }
            
            var terminatedIds: [AnyHashable] = []
            continuations.forEach { (id, cont) in
                switch cont.yield(element) {
                case .terminated:
                    terminatedIds.append(id)
                    AsyncStoreLog.warning("\(logTag) yield to terminated stream, id:\"\(id)\"")
                case .dropped(let element):
                    AsyncStoreLog.warning("\(logTag) dropped \(type(of: element))  id:\"\(id)\"")
                default:
                    break
                }
            }
            terminatedIds.forEach { continuations[$0] = .none }
        }
        
        func finish(_ id: AnyHashable) {
            continuations[id]?.finish()
            continuations[id] = .none
        }
        
        func finishAll() {
            continuations.forEach { $1.finish() }
            continuations = [:]
        }
    }
    
    public typealias BufferingPolicy = AsyncStream<Element>.Continuation.BufferingPolicy
    
    private var contActor = ContinuationActor()
    
    public init() {}
    
    public func count() async -> Int {
        return await contActor.count
    }
    
    public func stream(
        for id: AnyHashable,
        initialValue: Element,
        bufferingPolicy: BufferingPolicy
    ) -> AsyncStream<Element> {
        .init(bufferingPolicy: bufferingPolicy) { cont in
            Task {
                await contActor.add(cont, for: id)
                cont.yield(initialValue)
            }
        }
    }
    
    public func yield(_ element: Element) {
        Task { await contActor.yield(element) }
    }
    
    public func finish(_ id: AnyHashable) {
        Task { await contActor.finish(id) }
    }
    
    public func finishAll() {
        Task { await contActor.finishAll() }
    }
}
