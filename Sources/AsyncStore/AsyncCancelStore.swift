//
//  File.swift
//  
//
//  Created by Wendell Thompson on 3/29/22.
//

import Foundation

public struct AsyncCancelStore {
    actor CancelActor {
        var cancellables: [AnyHashable: () -> Void] = [:]
        
        func store(_ id: AnyHashable?, cancel: @escaping () -> Void) {
            guard let id = id else { return }
            cancellables[id] = cancel
        }
        
        func cancel(_ id: AnyHashable?) {
            guard let id = id else { return }
            cancellables[id]?()
        }
        
        func cancellAll() {
            cancellables.forEach { $1() }
        }
    }
    
    private let cancelActor = CancelActor()
    
    public func store(_ id: AnyHashable?, cancel: @escaping () -> Void) {
        Task { await cancelActor.store(id, cancel: cancel) }
    }
    
    public func cancel(_ id: AnyHashable?) {
        Task { await cancelActor.cancel(id) }
    }
    
    public func cancellAll() {
        Task { await cancelActor.cancellAll() }
    }
}
