//
//  AsyncStoreMacros.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/18/25.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct AsyncStoreMacros: CompilerPlugin {
    var providingMacros: [Macro.Type] = [
        Stringify.self
    ]
}

