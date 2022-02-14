//
//  ContinuationActor.swift
//  
//
//  Created by Wendell Thompson (AO) on 2/14/22.
//

import Foundation

actor ContinuationActor<Element> {
    private var continuations: [AnyHashable: AsyncStream<Element>.Continuation] = [:]
    
    func store(_ id: AnyHashable, continuation: AsyncStream<Element>.Continuation) {
        continuations[id] = continuation
    }
    
    func yieldForEach(_ value: Element) {
        var terminatedContinuations: [AnyHashable] = []
        continuations.forEach { (id, cont) in
            let result = cont.yield(value)
            switch result {
            case .terminated:
                cont.finish()
                terminatedContinuations.append(id)
            default:
                break
            }
        }
        terminatedContinuations.forEach { continuations[$0] = .none }
    }
    
    func finish(_ id: AnyHashable) {
        guard let cont = continuations[id] else { return }
        cont.finish()
        continuations[id] = .none
    }
}
