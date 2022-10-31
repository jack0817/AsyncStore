//
//  File.swift
//  
//
//  Created by Wendell Thompson on 3/29/22.
//

import Foundation

public class AsyncCancelStore {
    private let cancellables = AsyncAtomicStore<Task<Void, Never>>()
    
    func store(_ id: AnyHashable?, task: Task<Void, Never>) {
        guard let id = id else { return }
        self.cancel(id)
        cancellables[id] = task
        
        Task {
            await task.value
            if !task.isCancelled {
                cancellables[id] = .none
            }
        }
    }
    
    func cancel(_ id: AnyHashable?) {
        guard let id = id else { return }
        switch cancellables[id] {
        case .some(let task):
            task.cancel()
            cancellables[id] = .none
        default:
            break
        }
    }
    
    func cancellAll() {
        let ids = cancellables.keys()
        ids.forEach { cancel($0) }
        cancellables.clear()
    }
}
