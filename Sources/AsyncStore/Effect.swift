//
//  Effect.swift
//  
//
//  Created by Wendell Thompson (AO) on 2/14/22.
//

import Foundation

public extension AsyncStore {
    enum Effect {
        case none
        case set((inout State) -> Void)
        case task(operation: () async throws -> Effect, id: AnyHashable?)
        case sleep(TimeInterval)
        case cancel(AnyHashable)
        case merge(effects: [Effect])
        case concatenate(effects: [Effect])
    }
}

public extension AsyncStore.Effect {
    static func task(
        _ operation: @escaping () async throws -> Self,
        _ id: AnyHashable? = .none
    ) -> Self {
        .task(operation: operation, id: id)
    }
    
    static func merge(_ effects: Self ...) -> Self {
        .merge(effects: effects)
    }
    
    static func concatenate(_ effects: Self ...) -> Self {
        .concatenate(effects: effects)
    }
}
