//
//  File.swift
//  
//
//  Created by Wendell Thompson on 3/29/22.
//

import Foundation

public class AsyncCancelStore {
    private let cancellables = AsyncAtomicStore<() -> Void>()
    
    func store(_ id: AnyHashable?, cancel: @escaping () -> Void) {
        guard let id = id else { return }
        self.cancel(id)
        cancellables.set(id: id, to: cancel)
    }
    
    func cancel(_ id: AnyHashable?) {
        guard let id = id else { return }
        cancellables.get(id: id)?()
    }
    
    func cancellAll() {
        let ids = cancellables.keys()
        ids.forEach { cancel($0) }
        cancellables.clear()
    }
}
