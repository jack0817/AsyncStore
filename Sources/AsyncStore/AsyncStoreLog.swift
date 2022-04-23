//
//  File.swift
//  
//
//  Created by Wendell Thompson on 4/12/22.
//

import Foundation

public struct AsyncStoreLog {
    private static var output: ((String) -> Void)? = .none
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ss:SSS"
        return formatter
    }()
    
    @available(*, deprecated, message: "Use 'setOutput' instead")
    public static func setEnabled(_ enabled: Bool) { }
    
    public static func setOutput(_ output: @escaping (String) -> Void) {
        Self.output = output
    }
    
    static func log(_ message: String) {
        guard let output = Self.output else { return }
        let logMessage = [
            dateFormatter.string(from: Date()),
            "[🔄AsyncStore]",
            message
        ].joined(separator: " - ")
        output(logMessage)
    }
}
