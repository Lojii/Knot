//
//  SMTPDecoder.swift
//  TunnelServices
//
//  SMTP protocol decoder.
//  Netty reference: codec-smtp/SmtpRequest.java, SmtpResponse.java
//

import Foundation

public struct SMTPMessage {
    public enum MessageType {
        case command(String, String?)   // command name, parameter
        case response(Int, String)      // status code, text
        case data(String)               // email body
    }

    public let type: MessageType
    public let raw: String
}

public class SMTPParser {

    public static func parse(_ data: Data) -> [SMTPMessage] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var messages = [SMTPMessage]()
        var inData = false

        for line in text.components(separatedBy: "\r\n") {
            guard !line.isEmpty else { continue }

            if inData {
                if line == "." {
                    inData = false
                    messages.append(SMTPMessage(type: .data("<end of message>"), raw: "."))
                } else {
                    messages.append(SMTPMessage(type: .data(line), raw: line))
                }
                continue
            }

            // Check if it's a response (starts with 3-digit code)
            if line.count >= 3, let code = Int(line.prefix(3)) {
                let text = line.count > 4 ? String(line.dropFirst(4)) : ""
                messages.append(SMTPMessage(type: .response(code, text), raw: line))
                continue
            }

            // It's a command
            let parts = line.split(separator: " ", maxSplits: 1)
            let command = String(parts[0]).uppercased()
            let param = parts.count > 1 ? String(parts[1]) : nil
            messages.append(SMTPMessage(type: .command(command, param), raw: line))

            if command == "DATA" { inData = true }
        }
        return messages
    }

    public static func format(_ msg: SMTPMessage) -> String {
        switch msg.type {
        case .command(let cmd, let param):
            return "[SMTP] \(cmd)\(param.map { " \($0)" } ?? "")"
        case .response(let code, let text):
            return "[SMTP \(code)] \(text)"
        case .data(let content):
            return "[SMTP DATA] \(content.prefix(200))"
        }
    }

    public static func isSMTP(_ data: Data) -> Bool {
        guard let first = String(data: data.prefix(20), encoding: .utf8)?.uppercased() else { return false }
        return first.hasPrefix("220 ") || first.hasPrefix("EHLO") || first.hasPrefix("HELO")
    }
}
