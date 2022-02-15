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
    
    static func dataTask<Data>(
        _ data: Data,
        _ operation: @escaping (Data) async throws -> Self,
        _ id: AnyHashable? = .none
    ) -> Self {
        .task(operation: { try await operation(data) }, id: id)
    }
    
    static func merge(_ effects: Self ...) -> Self {
        .merge(effects: effects)
    }
    
    static func concatenate(_ effects: Self ...) -> Self {
        .concatenate(effects: effects)
    }
}

extension AsyncStore.Effect: CustomStringConvertible {
    public var description: String {
        switch self {
        case .none:
            return "None"
        case .set:
            return "Set(\(State.self))"
        case .task(_, let id):
            switch id {
            case .some(let id):
                return "Task(\(id))"
            default:
                return "Task"
            }
        case .sleep(let time):
            return "Sleep(\(time))"
        case .cancel(let id):
            return "Cancel(\(id))"
        case .merge(let effects):
            let effectsDesc = effects.map(\.description).split(separator: ", ")
            return "Merge(\(effectsDesc))"
        case .concatenate(let effects):
            let effectsDesc = effects.map(\.description).split(separator: ", ")
            return "Concatenate(\(effectsDesc))"
        }
    }
}
