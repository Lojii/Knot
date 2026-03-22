//
//  RedisDecoder.swift
//  TunnelServices
//
//  Redis RESP (REdis Serialization Protocol) decoder.
//
//  Netty reference: codec-redis/RedisDecoder.java, RedisEncoder.java
//

import Foundation
import NIO

// MARK: - Redis Value

public enum RedisValue {
    case simpleString(String)      // +OK\r\n
    case error(String)             // -ERR message\r\n
    case integer(Int64)            // :1000\r\n
    case bulkString(Data?)         // $5\r\nhello\r\n  or  $-1\r\n (nil)
    case array([RedisValue]?)      // *2\r\n...\r\n  or  *-1\r\n (nil)
}

// MARK: - Redis Parser

public class RedisParser {

    /// Parse RESP protocol data into RedisValue objects.
    public static func parse(_ data: Data) -> [RedisValue] {
        var offset = 0
        var results = [RedisValue]()
        while offset < data.count {
            guard let value = parseValue(data, at: &offset) else { break }
            results.append(value)
        }
        return results
    }

    /// Format a Redis command (array of values) as readable text.
    public static func formatCommand(_ values: [RedisValue]) -> String {
        guard case .array(let parts) = values.first, let parts = parts else {
            return values.map { formatValue($0) }.joined(separator: " ")
        }
        return parts.map { formatValue($0) }.joined(separator: " ")
    }

    /// Format a single RedisValue.
    public static func formatValue(_ value: RedisValue) -> String {
        switch value {
        case .simpleString(let s): return s
        case .error(let e): return "ERR: \(e)"
        case .integer(let i): return "\(i)"
        case .bulkString(let data):
            guard let data = data else { return "(nil)" }
            return String(data: data, encoding: .utf8) ?? "[\(data.count)B]"
        case .array(let arr):
            guard let arr = arr else { return "(nil)" }
            return "[\(arr.map { formatValue($0) }.joined(separator: ", "))]"
        }
    }

    // MARK: - RESP Parsing

    private static func parseValue(_ data: Data, at offset: inout Int) -> RedisValue? {
        guard offset < data.count else { return nil }
        let type = data[offset]
        offset += 1

        switch type {
        case 0x2B: // + Simple String
            guard let line = readLine(data, at: &offset) else { return nil }
            return .simpleString(line)

        case 0x2D: // - Error
            guard let line = readLine(data, at: &offset) else { return nil }
            return .error(line)

        case 0x3A: // : Integer
            guard let line = readLine(data, at: &offset) else { return nil }
            return .integer(Int64(line) ?? 0)

        case 0x24: // $ Bulk String
            guard let line = readLine(data, at: &offset), let length = Int(line) else { return nil }
            if length == -1 { return .bulkString(nil) }
            guard offset + length + 2 <= data.count else { return nil }
            let value = data[offset..<(offset + length)]
            offset += length + 2  // skip \r\n
            return .bulkString(Data(value))

        case 0x2A: // * Array
            guard let line = readLine(data, at: &offset), let count = Int(line) else { return nil }
            if count == -1 { return .array(nil) }
            var elements = [RedisValue]()
            for _ in 0..<count {
                guard let element = parseValue(data, at: &offset) else { break }
                elements.append(element)
            }
            return .array(elements)

        default:
            return nil
        }
    }

    private static func readLine(_ data: Data, at offset: inout Int) -> String? {
        guard let crIndex = data[offset...].firstIndex(of: 0x0D) else { return nil }
        let lineData = data[offset..<crIndex]
        offset = crIndex + 2  // skip \r\n
        return String(data: lineData, encoding: .utf8)
    }
}
