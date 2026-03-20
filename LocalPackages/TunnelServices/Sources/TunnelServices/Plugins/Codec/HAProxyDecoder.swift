//
//  HAProxyDecoder.swift
//  TunnelServices
//
//  HAProxy PROXY protocol v1/v2 decoder.
//  Preserves original client IP when behind a proxy chain.
//  Netty reference: codec-haproxy/HAProxyMessage.java
//

import Foundation
import NIO

// MARK: - HAProxy Message

public struct HAProxyMessage {
    public enum Version { case v1, v2 }
    public enum TransportProtocol { case tcp4, tcp6, udp4, udp6, unknown }

    public let version: Version
    public let proto: TransportProtocol
    public let sourceAddress: String
    public let sourcePort: UInt16
    public let destinationAddress: String
    public let destinationPort: UInt16
}

// MARK: - HAProxy Decoder

public class HAProxyDecoder {

    // V2 signature: 12 bytes
    private static let v2Signature: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A, 0x00, 0x0D, 0x0A, 0x51, 0x55, 0x49, 0x54, 0x0A]

    /// Detect and parse HAProxy PROXY protocol header.
    /// Returns the message and the number of bytes consumed.
    public static func decode(_ buffer: ByteBuffer) -> (HAProxyMessage, Int)? {
        // Try V1 first (text-based)
        if let result = decodeV1(buffer) { return result }
        // Try V2 (binary)
        if let result = decodeV2(buffer) { return result }
        return nil
    }

    // MARK: - V1: "PROXY TCP4 192.168.1.1 10.0.0.1 12345 80\r\n"

    private static func decodeV1(_ buffer: ByteBuffer) -> (HAProxyMessage, Int)? {
        guard buffer.readableBytes >= 8 else { return nil }
        guard let prefix = buffer.getString(at: buffer.readerIndex, length: 6), prefix == "PROXY " else { return nil }

        // Find \r\n
        guard let text = buffer.getString(at: buffer.readerIndex, length: min(buffer.readableBytes, 108)) else { return nil }
        guard let endIndex = text.range(of: "\r\n")?.lowerBound else { return nil }

        let line = String(text[..<endIndex])
        let consumed = text.distance(from: text.startIndex, to: endIndex) + 2
        let parts = line.split(separator: " ")
        guard parts.count >= 6 else { return nil }

        let proto: HAProxyMessage.TransportProtocol
        switch String(parts[1]) {
        case "TCP4": proto = .tcp4
        case "TCP6": proto = .tcp6
        case "UDP4": proto = .udp4
        case "UDP6": proto = .udp6
        default: proto = .unknown
        }

        let msg = HAProxyMessage(
            version: .v1, proto: proto,
            sourceAddress: String(parts[2]), sourcePort: UInt16(parts[4]) ?? 0,
            destinationAddress: String(parts[3]), destinationPort: UInt16(parts[5]) ?? 0
        )
        return (msg, consumed)
    }

    // MARK: - V2: Binary format

    private static func decodeV2(_ buffer: ByteBuffer) -> (HAProxyMessage, Int)? {
        guard buffer.readableBytes >= 16 else { return nil }

        // Check signature
        for i in 0..<12 {
            guard buffer.getInteger(at: buffer.readerIndex + i, as: UInt8.self) == v2Signature[i] else { return nil }
        }

        guard let versionCommand = buffer.getInteger(at: buffer.readerIndex + 12, as: UInt8.self),
              let familyProto = buffer.getInteger(at: buffer.readerIndex + 13, as: UInt8.self),
              let addrLen = buffer.getInteger(at: buffer.readerIndex + 14, as: UInt16.self) else { return nil }

        let headerLen = 16 + Int(addrLen)
        guard buffer.readableBytes >= headerLen else { return nil }

        let family = (familyProto >> 4) & 0x0F
        let proto: HAProxyMessage.TransportProtocol
        var srcAddr = "", dstAddr = ""
        var srcPort: UInt16 = 0, dstPort: UInt16 = 0

        let addrOffset = buffer.readerIndex + 16

        switch family {
        case 0x1: // AF_INET (IPv4)
            proto = .tcp4
            if addrLen >= 12 {
                srcAddr = readIPv4(buffer, at: addrOffset)
                dstAddr = readIPv4(buffer, at: addrOffset + 4)
                srcPort = buffer.getInteger(at: addrOffset + 8, as: UInt16.self) ?? 0
                dstPort = buffer.getInteger(at: addrOffset + 10, as: UInt16.self) ?? 0
            }
        case 0x2: // AF_INET6 (IPv6)
            proto = .tcp6
            srcAddr = "<ipv6>"; dstAddr = "<ipv6>"
            if addrLen >= 36 {
                srcPort = buffer.getInteger(at: addrOffset + 32, as: UInt16.self) ?? 0
                dstPort = buffer.getInteger(at: addrOffset + 34, as: UInt16.self) ?? 0
            }
        default:
            proto = .unknown
        }

        let msg = HAProxyMessage(
            version: .v2, proto: proto,
            sourceAddress: srcAddr, sourcePort: srcPort,
            destinationAddress: dstAddr, destinationPort: dstPort
        )
        return (msg, headerLen)
    }

    private static func readIPv4(_ buffer: ByteBuffer, at offset: Int) -> String {
        guard let a = buffer.getInteger(at: offset, as: UInt8.self),
              let b = buffer.getInteger(at: offset+1, as: UInt8.self),
              let c = buffer.getInteger(at: offset+2, as: UInt8.self),
              let d = buffer.getInteger(at: offset+3, as: UInt8.self) else { return "0.0.0.0" }
        return "\(a).\(b).\(c).\(d)"
    }

    public static func format(_ msg: HAProxyMessage) -> String {
        "[PROXY v\(msg.version == .v1 ? "1" : "2")] \(msg.proto) \(msg.sourceAddress):\(msg.sourcePort) → \(msg.destinationAddress):\(msg.destinationPort)"
    }
}
