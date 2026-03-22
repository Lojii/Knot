//
//  GRPCCaptureHandler.swift
//  TunnelServices
//
//  Pure gRPC protocol decoder. No NIO pipeline logic.
//  Used by HTTP2CaptureHandler when content-type: application/grpc is detected.
//
//  gRPC wire format:
//    +------------+-----------+----------------------------+
//    | Compressed | Length    | Message (protobuf)         |
//    | (1 byte)   | (4 bytes) | (Length bytes)             |
//    +------------+-----------+----------------------------+
//

import Foundation
import NIO
import NIOHTTP1

// MARK: - gRPC Frame Parser

/// Parses the gRPC Length-Prefixed Message framing format.
public struct GRPCFrameParser {

    public struct Message {
        public let compressed: Bool
        public let data: Data
    }

    /// Parse all gRPC messages from a ByteBuffer.
    public static func parse(_ buffer: ByteBuffer) -> [Message] {
        var buf = buffer
        var messages = [Message]()

        while buf.readableBytes >= 5 {
            guard let compressedByte = buf.getInteger(at: buf.readerIndex, as: UInt8.self),
                  let length = buf.getInteger(at: buf.readerIndex + 1, as: UInt32.self) else {
                break
            }

            let totalSize = 5 + Int(length)
            guard buf.readableBytes >= totalSize else { break }

            buf.moveReaderIndex(forwardBy: 5)
            if let bytes = buf.readBytes(length: Int(length)) {
                messages.append(Message(compressed: compressedByte == 1, data: Data(bytes)))
            }
        }

        return messages
    }

    /// Format a gRPC message as human-readable text.
    public static func formatMessage(_ message: Message, maxLength: Int = 1024) -> String {
        if message.compressed {
            return "<compressed \(message.data.count) bytes>"
        }
        if let decoded = ProtobufDecoder.decode(message.data) {
            let text = decoded.prefix(maxLength)
            return text + (decoded.count > maxLength ? "...(truncated)" : "")
        }
        return HexFormatter.format(message.data, maxLength: maxLength)
    }
}

// MARK: - gRPC Status Codes

public enum GRPCStatus {
    public static func name(for code: String) -> String {
        switch code {
        case "0": return "OK"
        case "1": return "CANCELLED"
        case "2": return "UNKNOWN"
        case "3": return "INVALID_ARGUMENT"
        case "4": return "DEADLINE_EXCEEDED"
        case "5": return "NOT_FOUND"
        case "6": return "ALREADY_EXISTS"
        case "7": return "PERMISSION_DENIED"
        case "8": return "RESOURCE_EXHAUSTED"
        case "9": return "FAILED_PRECONDITION"
        case "10": return "ABORTED"
        case "11": return "OUT_OF_RANGE"
        case "12": return "UNIMPLEMENTED"
        case "13": return "INTERNAL"
        case "14": return "UNAVAILABLE"
        case "15": return "DATA_LOSS"
        case "16": return "UNAUTHENTICATED"
        default: return "STATUS_\(code)"
        }
    }
}

// MARK: - gRPC Decoder (used by H2StreamCaptureHandler)

/// Utility methods for logging gRPC body and trailers.
/// Called by HTTP2CaptureHandler when gRPC content-type is detected.
public enum GRPCDecoder {

    public static func logRequestBody(_ body: ByteBuffer, recorder: SessionRecorder) {
        let messages = GRPCFrameParser.parse(body)
        for (i, msg) in messages.enumerated() {
            let formatted = GRPCFrameParser.formatMessage(msg)
            appendLog("  [REQ #\(i+1)] \(formatted)\n", to: .REQ, recorder: recorder)
        }
    }

    public static func logResponseBody(_ body: ByteBuffer, recorder: SessionRecorder) {
        let messages = GRPCFrameParser.parse(body)
        for (i, msg) in messages.enumerated() {
            let formatted = GRPCFrameParser.formatMessage(msg)
            appendLog("  [RSP #\(i+1)] \(formatted)\n", to: .RSP, recorder: recorder)
        }
    }

    public static func logTrailers(_ trailers: HTTPHeaders?, recorder: SessionRecorder) {
        guard let trailers = trailers,
              let status = trailers.first(name: "grpc-status") else { return }
        let message = trailers.first(name: "grpc-message") ?? ""
        let statusName = GRPCStatus.name(for: status)
        appendLog("[gRPC Status] \(statusName) (\(status)) \(message)\n", to: .RSP, recorder: recorder)
    }

    private static func appendLog(_ text: String, to fileType: FileType, recorder: SessionRecorder) {
        guard let data = text.data(using: .utf8) else { return }
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        if fileType == .REQ {
            recorder.recordRequestBody(buffer)
        } else {
            recorder.recordResponseBody(buffer)
        }
    }
}

// MARK: - Protobuf Wire Format Decoder (no schema required)

/// Decodes raw protobuf without a .proto schema.
/// Shows field numbers and values: "f1: 42, f2: \"hello\""
public enum ProtobufDecoder {

    public static func decode(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard let fields = decodeFields(data), !fields.isEmpty else { return nil }
        return fields.joined(separator: ", ")
    }

    private static func decodeFields(_ data: Data) -> [String]? {
        var fields = [String]()
        var offset = 0

        while offset < data.count {
            guard let (tag, tagLen) = readVarint(data, at: offset) else { break }
            offset += tagLen

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            switch wireType {
            case 0: // varint
                guard let (value, valLen) = readVarint(data, at: offset) else { return fields.isEmpty ? nil : fields }
                offset += valLen
                fields.append("f\(fieldNumber): \(value)")
            case 1: // 64-bit fixed
                guard offset + 8 <= data.count else { return fields.isEmpty ? nil : fields }
                offset += 8
                fields.append("f\(fieldNumber): <64bit>")
            case 2: // length-delimited
                guard let (length, lenLen) = readVarint(data, at: offset) else { return fields.isEmpty ? nil : fields }
                offset += lenLen
                let end = offset + Int(length)
                guard end <= data.count else { return fields.isEmpty ? nil : fields }
                let bytes = data[offset..<end]
                if let str = String(data: bytes, encoding: .utf8),
                   str.allSatisfy({ $0.isASCII && !$0.isNewline }) {
                    fields.append("f\(fieldNumber): \"\(str.prefix(200))\"")
                } else {
                    fields.append("f\(fieldNumber): <\(length)B>")
                }
                offset = end
            case 5: // 32-bit fixed
                guard offset + 4 <= data.count else { return fields.isEmpty ? nil : fields }
                offset += 4
                fields.append("f\(fieldNumber): <32bit>")
            default:
                return fields.isEmpty ? nil : fields
            }
        }

        return fields.isEmpty ? nil : fields
    }

    private static func readVarint(_ data: Data, at offset: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var pos = offset
        while pos < data.count {
            let byte = data[pos]
            result |= UInt64(byte & 0x7F) << shift
            pos += 1
            if byte & 0x80 == 0 { return (result, pos - offset) }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
}

// MARK: - Hex Formatter

public enum HexFormatter {

    public static func format(_ data: Data, maxLength: Int = 1024) -> String {
        let preview = data.prefix(min(data.count, maxLength / 2))
        let hex = preview.map { String(format: "%02x", $0) }.joined(separator: " ")
        let ascii = String(preview.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." })
        var result = "[\(data.count)B] \(hex)"
        if !ascii.isEmpty { result += " | \(ascii)" }
        if data.count > maxLength / 2 { result += "..." }
        return result
    }
}
