//
//  AsyncStoreMacros.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/18/25.
//

import Foundation

@freestanding(expression)
public macro Stringify(
    _ value: Any
) -> String = #externalMacro(
    module: "AsyncStoreMacros",
    type: "Stringify"
)
