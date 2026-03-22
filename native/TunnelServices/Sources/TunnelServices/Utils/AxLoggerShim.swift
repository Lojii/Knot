// AxLoggerShim.swift
// Minimal shim for AxLogger until Task 4 migrates it properly.

import Foundation
import os

/// Replacement log-level enum matching the original AxLogger API.
@objc public enum AxLoggerLevel: Int, CustomStringConvertible {
    case Error = 0
    case Warning = 1
    case Info = 2
    case Notify = 3
    case Trace = 4
    case Verbose = 5
    case Debug = 6
    public var description: String {
        switch self {
        case .Error:   return "Error"
        case .Warning: return "Warning"
        case .Info:    return "Info"
        case .Notify:  return "Notify"
        case .Trace:   return "Trace"
        case .Verbose: return "Verbose"
        case .Debug:   return "Debug"
        }
    }
}

/// Minimal AxLogger shim that forwards to os.Logger.
public final class AxLogger: NSObject {
    private static let logger = os.Logger(subsystem: "com.knot.tunnelservices", category: "AxLogger")

    public static func openLogging(_ baseURL: URL, date: Date, debug: Bool = false) {
        logger.info("AxLogger.openLogging called (shim, no-op)")
    }

    @objc public static func log(
        _ msg: String,
        level: AxLoggerLevel,
        category: String = "default",
        file: String = #file,
        line: Int = #line,
        ud: [String: String] = [:],
        tags: [String] = [],
        time: Date = Date()
    ) {
        switch level {
        case .Error:
            logger.error("\(msg, privacy: .public)")
        case .Warning:
            logger.warning("\(msg, privacy: .public)")
        case .Info, .Notify:
            logger.info("\(msg, privacy: .public)")
        case .Trace, .Verbose, .Debug:
            logger.debug("\(msg, privacy: .public)")
        }
    }
}
