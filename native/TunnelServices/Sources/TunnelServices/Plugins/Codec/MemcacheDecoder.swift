//
//  MemcacheDecoder.swift
//  TunnelServices
//
//  Memcached text protocol decoder.
//  Netty reference: codec-memcache/MemcacheMessage.java
//

import Foundation

public struct MemcacheCommand {
    public enum CommandType: String {
        case get = "get", gets = "gets", set = "set", add = "add", replace = "replace"
        case append = "append", prepend = "prepend", cas = "cas"
        case delete = "delete", incr = "incr", decr = "decr"
        case stats = "stats", flushAll = "flush_all", version = "version", quit = "quit"
        case unknown
    }

    public let type: CommandType
    public let key: String?
    public let flags: UInt32?
    public let exptime: Int?
    public let bytes: Int?
    public let value: Data?
    public let rawLine: String
}

public class MemcacheParser {

    public static func parse(_ data: Data) -> [MemcacheCommand] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var commands = [MemcacheCommand]()
        let lines = text.components(separatedBy: "\r\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            guard !line.isEmpty else { i += 1; continue }
            let parts = line.split(separator: " ", maxSplits: 10).map(String.init)
            guard let cmdStr = parts.first else { i += 1; continue }

            let type = MemcacheCommand.CommandType(rawValue: cmdStr.lowercased()) ?? .unknown

            switch type {
            case .set, .add, .replace, .append, .prepend, .cas:
                let key = parts.count > 1 ? parts[1] : nil
                let flags = parts.count > 2 ? UInt32(parts[2]) : nil
                let exptime = parts.count > 3 ? Int(parts[3]) : nil
                let bytes = parts.count > 4 ? Int(parts[4]) : nil
                var value: Data? = nil
                if let bytes = bytes, i + 1 < lines.count {
                    i += 1
                    value = lines[i].prefix(bytes).data(using: .utf8)
                }
                commands.append(MemcacheCommand(type: type, key: key, flags: flags,
                    exptime: exptime, bytes: bytes, value: value, rawLine: line))

            case .get, .gets:
                let keys = Array(parts.dropFirst())
                for key in keys {
                    commands.append(MemcacheCommand(type: type, key: key, flags: nil,
                        exptime: nil, bytes: nil, value: nil, rawLine: line))
                }

            default:
                let key = parts.count > 1 ? parts[1] : nil
                commands.append(MemcacheCommand(type: type, key: key, flags: nil,
                    exptime: nil, bytes: nil, value: nil, rawLine: line))
            }
            i += 1
        }
        return commands
    }

    public static func format(_ cmd: MemcacheCommand) -> String {
        var parts = ["[\(cmd.type.rawValue.uppercased())]"]
        if let key = cmd.key { parts.append("key=\(key)") }
        if let bytes = cmd.bytes { parts.append("size=\(bytes)B") }
        if let value = cmd.value, let str = String(data: value.prefix(200), encoding: .utf8) {
            parts.append("value=\"\(str)\"")
        }
        return parts.joined(separator: " ")
    }

    public static func isMemcache(_ data: Data) -> Bool {
        guard let first = String(data: data.prefix(20), encoding: .utf8)?.lowercased() else { return false }
        let cmds = ["get ", "set ", "add ", "delete ", "incr ", "decr ", "stats", "version", "flush_all"]
        return cmds.contains(where: { first.hasPrefix($0) })
    }
}
