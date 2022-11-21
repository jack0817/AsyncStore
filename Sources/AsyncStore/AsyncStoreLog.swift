//
//  AsyncStoreLog.swift
//  
//
//  Created by Wendell Thompson on 4/12/22.
//

import Foundation

public struct AsyncStoreLog {
    public private(set) static var level: AsyncStoreLog.Level = .debug
    private static var output: ((String) -> Void)? = .none
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ss:SSS"
        return formatter
    }()
    
    public static func setLevel(_ level: AsyncStoreLog.Level) {
        Self.level = level
    }
    
    public static func setOutput(_ output: ((String) -> Void)?) {
        Self.output = output
    }
    
    internal static func error(_ error: Error) {
        Self.error("\(error)")
    }
    
    internal static func error(_ msg: String) {
        log(.error, msg)
    }
    
    internal static func debug(_ msg: String) {
        log(.debug, msg)
    }
    
    internal static func warning(_ msg: String) {
        log(.warning, msg)
    }
    
    internal static func info(_ msg: String) {
        log(.info, msg)
    }
    
    fileprivate static func log(_ level: AsyncStoreLog.Level, _ message: String) {
        guard let output = Self.output, level.rawValue <= Self.level.rawValue else { return }
        let logMessage = [
            dateFormatter.string(from: Date()),
            "[🔄AsyncStore]",
            level.tag,
            message
        ].joined(separator: " - ")
        output(logMessage)
    }
}

extension AsyncStoreLog {
    public enum Level: Int {
        case error = 0
        case debug = 1
        case warning = 2
        case info = 3
        
        var tag: String {
            switch self {
            case .error: return "[ERROR]"
            case .debug: return "[DEBUG]"
            case .warning: return "[WARNING]"
            case .info: return "[INFO]"
            }
        }
    }
}
