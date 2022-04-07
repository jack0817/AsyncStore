//
//  File.swift
//  
//
//  Created by Wendell Thompson on 3/29/22.
//

import Foundation

public actor AsyncCancelStore {
    private var cancellables: [AnyHashable: () -> Void] = [:]
    
    deinit {
        cancellAll()
    }
    
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
        cancellables = [:]
    }
}
