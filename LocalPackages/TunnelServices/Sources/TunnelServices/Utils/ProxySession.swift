//
//  ProxySession.swift
//  TunnelServices
//
//  Lightweight in-memory session data holder.
//  Replaces the legacy Session ASModel class for handler use.
//  No database dependency — persistence is handled by SessionRecorder + FlowDAO.
//

import Foundation

public class ProxySession {
    // Request
    public var taskID: String = ""
    public var remoteAddress: String = ""
    public var localAddress: String = ""
    public var host: String = ""
    public var schemes: String = ""     // "Http", "Https", "WS", "WSS", "H2"
    public var methods: String = ""
    public var uri: String = ""
    public var suffix: String = ""
    public var reqLine: String = ""
    public var reqHttpVersion: String = ""
    public var reqType: String = ""
    public var reqEncoding: String = ""
    public var reqHeads: String = ""
    public var reqBody: String = ""
    public var reqDisposition: String = ""
    public var target: String = ""       // User-Agent

    // Response
    public var rspHttpVersion: String = ""
    public var state: String = ""        // status code as string
    public var rspMessage: String = ""
    public var rspType: String = ""
    public var rspEncoding: String = ""
    public var rspHeads: String = ""
    public var rspBody: String = ""
    public var rspDisposition: String = ""

    // Timing
    public var startTime: TimeInterval = 0
    public var connectTime: TimeInterval = 0
    public var connectedTime: TimeInterval = 0
    public var handshakeEndTime: TimeInterval = 0
    public var reqEndTime: TimeInterval = 0
    public var rspStartTime: TimeInterval = 0
    public var rspEndTime: TimeInterval = 0
    public var endTime: TimeInterval = 0

    // Traffic
    public var uploadTraffic: Int64 = 0
    public var downloadFlow: Int64 = 0

    // State
    public var sstate: String = ""       // "success" / "failure"
    public var inState: String = ""
    public var outState: String = ""
    public var ignore: Bool = false
    public var note: String = ""

    // File
    public var fileName: String = ""
    public var fileFolder: String = ""

    public init() {
        self.startTime = Date().timeIntervalSince1970
    }

    public func getFullUrl() -> String {
        let u = uri
        let s = schemes.lowercased()
        let h = host
        guard !u.isEmpty, !s.isEmpty, !h.isEmpty else {
            return ""
        }
        if u.first == "/" {
            return "\(s)://\(h)\(u)"
        }
        if u.contains("://") {
            return u
        } else {
            return "\(s)://\(u)"
        }
    }
}
