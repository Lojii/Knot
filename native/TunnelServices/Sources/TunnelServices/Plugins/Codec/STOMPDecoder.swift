//
//  STOMPDecoder.swift
//  TunnelServices
//
//  STOMP (Simple Text Oriented Messaging Protocol) decoder.
//  Commonly used over WebSocket for real-time messaging.
//  Netty reference: codec-stomp/StompSubframeDecoder.java
//

import Foundation

public struct STOMPFrame {
    public enum Command: String {
        // Client commands
        case connect = "CONNECT", stomp = "STOMP", send = "SEND"
        case subscribe = "SUBSCRIBE", unsubscribe = "UNSUBSCRIBE"
        case ack = "ACK", nack = "NACK", begin = "BEGIN"
        case commit = "COMMIT", abort = "ABORT", disconnect = "DISCONNECT"
        // Server commands
        case connected = "CONNECTED", message = "MESSAGE"
        case receipt = "RECEIPT", error = "ERROR"
        case unknown = "UNKNOWN"
    }

    public let command: Command
    public let headers: [(String, String)]
    public let body: String?

    public var destination: String? { headers.first(where: { $0.0 == "destination" })?.1 }
    public var contentType: String? { headers.first(where: { $0.0 == "content-type" })?.1 }
    public var messageId: String? { headers.first(where: { $0.0 == "message-id" })?.1 }
    public var subscription: String? { headers.first(where: { $0.0 == "subscription" })?.1 }
}

public class STOMPParser {

    /// Parse STOMP frames from a text payload (typically from WebSocket TEXT frames).
    public static func parse(_ text: String) -> [STOMPFrame] {
        var frames = [STOMPFrame]()
        // STOMP frames are separated by NULL character (0x00)
        let rawFrames = text.components(separatedBy: "\0").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for raw in rawFrames {
            if let frame = parseFrame(raw) {
                frames.append(frame)
            }
        }
        return frames
    }

    private static func parseFrame(_ raw: String) -> STOMPFrame? {
        let lines = raw.components(separatedBy: "\n")
        guard let commandLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !commandLine.isEmpty else { return nil }

        let command = STOMPFrame.Command(rawValue: commandLine.uppercased()) ?? .unknown
        var headers = [(String, String)]()
        var bodyStartIndex = 1

        // Parse headers (key:value)
        for i in 1..<lines.count {
            let line = lines[i].replacingOccurrences(of: "\r", with: "")
            if line.isEmpty {
                bodyStartIndex = i + 1
                break
            }
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers.append((String(parts[0]), String(parts[1])))
            }
            bodyStartIndex = i + 1
        }

        // Parse body
        let body: String?
        if bodyStartIndex < lines.count {
            body = lines[bodyStartIndex...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            body = nil
        }

        return STOMPFrame(command: command, headers: headers, body: body?.isEmpty == true ? nil : body)
    }

    public static func format(_ frame: STOMPFrame) -> String {
        var parts = ["[STOMP \(frame.command.rawValue)]"]
        if let dest = frame.destination { parts.append("dest=\(dest)") }
        if let msgId = frame.messageId { parts.append("id=\(msgId)") }
        if let body = frame.body {
            parts.append("body=\"\(body.prefix(200))\"")
        }
        return parts.joined(separator: " ")
    }

    /// Check if a WebSocket text frame contains STOMP protocol data.
    public static func isSTOMP(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let commands = ["CONNECT", "STOMP", "CONNECTED", "SEND", "SUBSCRIBE",
                       "MESSAGE", "RECEIPT", "ERROR", "DISCONNECT"]
        return commands.contains(where: { trimmed.hasPrefix($0 + "\n") || trimmed.hasPrefix($0 + "\r") })
    }
}

