import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPluginMessageHandling

public enum Stringify: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        // Expect exactly one argument expression
        guard let argument = node.argumentList.first?.expression else {
            throw StringifyError.message("#Stringify requires one argument")
        }

        // Build: String(describing: <argument>)
        let call: ExprSyntax = "String(describing: \(argument))"
        return call
    }
}

public enum StringifyError: Error {
    case message(String)
}
