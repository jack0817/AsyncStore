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
        private var continuations: [AnyHashable: AsyncStream<Element>.Continuation] = [:]
        
        deinit {
            finishAll()
        }
        
        func add(_ stream: AsyncStream<Element>.Continuation, for id: AnyHashable) {
            finish(id)
            continuations[id] = stream
        }
        
        func yield(_ element: Element) {
            var terminatedIds: [AnyHashable] = []
            continuations.forEach { (id, cont) in
                switch cont.yield(element) {
                case .terminated:
                    terminatedIds.append(id)
                    AsyncStoreLog.log("[AsyncDistributor<\(type(of: element))>] yield to terminated stream \"\(id)\"")
                case .dropped(let element):
                    AsyncStoreLog.log("[AsyncDistributor<\(type(of: element))>] dropped \"\(element)\"")
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
