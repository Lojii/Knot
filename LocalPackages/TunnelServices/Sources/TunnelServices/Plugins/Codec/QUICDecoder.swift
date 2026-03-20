//
//  QUICDecoder.swift
//  TunnelServices
//
//  QUIC protocol header decoder (RFC 9000).
//  QUIC uses UDP port 443, forming the transport layer for HTTP/3.
//  We can parse the initial unencrypted header to extract connection info.
//

import Foundation

// MARK: - QUIC Packet Header

public struct QUICPacketHeader {
    public let isLongHeader: Bool
    public let version: UInt32?           // Only in long headers
    public let dcidLength: Int
    public let dcid: Data                 // Destination Connection ID
    public let scidLength: Int?
    public let scid: Data?               // Source Connection ID (long header only)
    public let packetType: PacketType
    public let payloadLength: Int

    public enum PacketType: String {
        case initial = "Initial"
        case zeroRTT = "0-RTT"
        case handshake = "Handshake"
        case retry = "Retry"
        case shortHeader = "Short"
        case unknown = "Unknown"
    }

    /// Known QUIC versions
    public var versionName: String? {
        guard let v = version else { return nil }
        switch v {
        case 0x00000001: return "QUIC v1 (RFC 9000)"
        case 0x6b3343cf: return "QUIC v2 (RFC 9369)"
        case 0xff000000...0xff0000ff:
            return "Draft \(v & 0xFF)"
        case 0: return "Version Negotiation"
        default: return "0x\(String(v, radix: 16))"
        }
    }
}

// MARK: - QUIC Decoder

public class QUICDecoder {

    /// Parse QUIC packet header from UDP payload.
    /// Only the unencrypted header fields can be parsed.
    public static func parseHeader(_ data: Data) -> QUICPacketHeader? {
        guard !data.isEmpty else { return nil }

        let firstByte = data[0]
        let isLongHeader = (firstByte & 0x80) != 0

        if isLongHeader {
            return parseLongHeader(data)
        } else {
            return parseShortHeader(data)
        }
    }

    // MARK: - Long Header (Initial, Handshake, 0-RTT, Retry)

    private static func parseLongHeader(_ data: Data) -> QUICPacketHeader? {
        // Long Header format:
        //   1 byte:  flags (1FTTNNNN) F=fixed, TT=type, NNNN=pktnum len
        //   4 bytes: version
        //   1 byte:  DCID length
        //   N bytes: DCID
        //   1 byte:  SCID length
        //   N bytes: SCID
        //   ...

        guard data.count >= 7 else { return nil }
        let flags = data[0]
        let version = readUInt32(data, at: 1)

        let dcidLen = Int(data[5])
        guard data.count >= 6 + dcidLen + 1 else { return nil }
        let dcid = Data(data[6..<(6 + dcidLen)])

        let scidLenOffset = 6 + dcidLen
        let scidLen = Int(data[scidLenOffset])
        guard data.count >= scidLenOffset + 1 + scidLen else { return nil }
        let scid = Data(data[(scidLenOffset + 1)..<(scidLenOffset + 1 + scidLen)])

        // Determine packet type from flags
        let typeBits = (flags >> 4) & 0x03
        let packetType: QUICPacketHeader.PacketType
        if version == 0 {
            packetType = .unknown  // Version Negotiation
        } else {
            switch typeBits {
            case 0: packetType = .initial
            case 1: packetType = .zeroRTT
            case 2: packetType = .handshake
            case 3: packetType = .retry
            default: packetType = .unknown
            }
        }

        return QUICPacketHeader(
            isLongHeader: true, version: version,
            dcidLength: dcidLen, dcid: dcid,
            scidLength: scidLen, scid: scid,
            packetType: packetType,
            payloadLength: data.count - scidLenOffset - 1 - scidLen
        )
    }

    // MARK: - Short Header (1-RTT, after handshake)

    private static func parseShortHeader(_ data: Data) -> QUICPacketHeader? {
        // Short Header format:
        //   1 byte:  flags (0FSKNNNN)
        //   N bytes: DCID (length known from connection state, assume max 20)
        guard data.count >= 2 else { return nil }

        // We don't know the DCID length without connection state
        // Use heuristic: assume common lengths (8 or 0)
        let dcidLen = min(8, data.count - 1)
        let dcid = dcidLen > 0 ? Data(data[1..<(1 + dcidLen)]) : Data()

        return QUICPacketHeader(
            isLongHeader: false, version: nil,
            dcidLength: dcidLen, dcid: dcid,
            scidLength: nil, scid: nil,
            packetType: .shortHeader,
            payloadLength: data.count - 1 - dcidLen
        )
    }

    // MARK: - SNI Extraction (from Initial packet)

    /// Try to extract SNI (Server Name) from a QUIC Initial packet.
    /// The Initial packet contains a TLS ClientHello inside CRYPTO frames.
    public static func extractSNI(_ data: Data) -> String? {
        // QUIC Initial packets contain TLS ClientHello in CRYPTO frames
        // The ClientHello is encrypted with initial keys derived from the DCID
        // Full SNI extraction requires TLS parsing - simplified here
        // Look for cleartext SNI pattern (may not work with all implementations)

        guard let header = parseHeader(data), header.packetType == .initial else { return nil }

        // Search for SNI extension pattern in the payload
        // TLS SNI extension type = 0x0000, followed by length + name
        // This is a best-effort heuristic scan
        let payload = data
        for i in 0..<(payload.count - 10) {
            // Look for: 00 00 (SNI type) followed by reasonable lengths
            if payload[i] == 0x00 && payload[i+1] == 0x00 {
                let outerLen = Int(payload[i+2]) << 8 | Int(payload[i+3])
                let listLen = Int(payload[i+4]) << 8 | Int(payload[i+5])
                let hostType = payload[i+6]
                let hostLen = Int(payload[i+7]) << 8 | Int(payload[i+8])

                if hostType == 0x00 && hostLen > 0 && hostLen < 256 &&
                   outerLen == listLen + 2 && listLen == hostLen + 3 {
                    let start = i + 9
                    let end = start + hostLen
                    if end <= payload.count {
                        if let name = String(data: payload[start..<end], encoding: .utf8),
                           name.contains(".") && !name.contains(" ") {
                            return name
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Format

    public static func format(_ header: QUICPacketHeader) -> String {
        var parts = ["[QUIC \(header.packetType.rawValue)]"]
        if let ver = header.versionName { parts.append("ver=\(ver)") }
        if !header.dcid.isEmpty {
            parts.append("dcid=\(header.dcid.prefix(8).map { String(format: "%02x", $0) }.joined())")
        }
        if let scid = header.scid, !scid.isEmpty {
            parts.append("scid=\(scid.prefix(8).map { String(format: "%02x", $0) }.joined())")
        }
        parts.append("\(header.payloadLength)B")
        return parts.joined(separator: " ")
    }

    /// Detect if UDP payload is QUIC.
    public static func isQUIC(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let firstByte = data[0]
        // Long header: first bit = 1, second bit = 1 (fixed bit)
        if (firstByte & 0xC0) == 0xC0 {
            // Check for known QUIC version
            guard data.count >= 5 else { return false }
            let version = readUInt32(data, at: 1)
            return version == 0x00000001 || version == 0x6b3343cf || (version & 0xFF000000) == 0xFF000000
        }
        return false
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 |
               UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])
    }
}
