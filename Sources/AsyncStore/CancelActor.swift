//
//  CancelActor.swift
//  
//
//  Created by Wendell Thompson (AO) on 2/14/22.
//

import Foundation

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
}
