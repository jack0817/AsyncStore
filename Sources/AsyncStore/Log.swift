//
//  File.swift
//  
//
//  Created by Wendell Thompson on 4/12/22.
//

import Foundation

public struct AsyncStoreLog {
    private static var isEnabled = false
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ss:SSS"
        return formatter
    }()
    
    public static func setEnabld(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    static func log(_ message: String) {
        guard isEnabled else { return }
        let logMessage = [
            "[AsyncStore]",
            dateFormatter.string(from: Date()),
            message
        ].joined(separator: " - ")
        print(logMessage)
    }
}
