//
//  AsyncStoreLogger.swift
//  AsyncStore
//
//  Created by Wendell Thompson on 12/22/25.
//

import Foundation
import os

public struct AsyncStoreLogger: Sendable {
    enum Level: Int, Sendable {
        case error
        case debug
        case warning
        case info
        
        public var tag: String {
            switch self {
            case .error: "[ERROR]"
            case .debug: "[DEBUG]"
            case .warning: "[WARNING]"
            case .info: "[INFO]"
            }
        }
    }
    
    struct Log: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        public let level: Level
        public let message: String
        public let date: Date
        
        init(level: Level, message: String) {
            self.level = level
            self.message = message
            self.date = .now
        }
        
        private static let dateFormatter: DateFormatter = {
           let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd hh:mm:ss:SSSS"
            return formatter
        }()
        
        var description: String {
            debugDescription
        }
        
        var debugDescription: String {
            [
                Self.dateFormatter.string(from: date),
                level.tag,
                message
            ].joined(separator: " - ")
        }
    }
    
    let level: Level
    
    init(_ level: Level = .debug) {
        self.level = level
    }
    
    func error(_ error: Swift.Error) {
        self.error("\(error)")
    }
    
    func error(_ message: String) {
        log(.error, message: message)
    }
    
    func debug(_ message: String) {
        log(.debug, message: message)
    }
    
    func warning(_ message: String) {
        log(.warning, message: message)
    }
    
    func info(_ message: String) {
        log(.info, message: message)
    }
    
    private func log(_ level: Level, message: String) {
        guard level.rawValue <= self.level.rawValue else { return }
        let log = Log(level: level, message: message)
        
        switch level {
        case .error:
            Logger.asyncStore.error("\(log)")
        case .debug:
            Logger.asyncStore.debug("\(log)")
        case .warning:
            Logger.asyncStore.warning("\(log)")
        case .info:
            Logger.asyncStore.info("\(log)")
        }
    }
}

fileprivate extension Logger {
    static var subsystem: String { Bundle.main.bundleIdentifier ?? "AsyncStore" }
    static let asyncStore = Logger(subsystem: subsystem, category: "asynsStore")
}
