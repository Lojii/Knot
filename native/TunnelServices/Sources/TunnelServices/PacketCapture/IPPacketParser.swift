//
//  IPPacketParser.swift
//  TunnelServices
//
//  Parses raw IP packets (IPv4/IPv6) and extracts TCP/UDP/ICMP headers.
//  Used by PacketTunnelProvider to inspect all network traffic.
//

import Foundation

// MARK: - IP Packet

public struct IPPacket {
    public let version: UInt8          // 4 or 6
    public let proto: IPProtocol
    public let sourceIP: String
    public let destinationIP: String
    public let totalLength: Int
    public let ttl: UInt8
    public let headerLength: Int       // IP header length in bytes
    public let payload: Data           // everything after IP header

    // Transport layer (populated based on protocol)
    public var tcpHeader: TCPHeader?
    public var udpHeader: UDPHeader?
    public var icmpHeader: ICMPHeader?

    /// The application payload (after transport header)
    public var applicationData: Data {
        switch proto {
        case .tcp:
            guard let tcp = tcpHeader else { return payload }
            return tcp.dataOffset < payload.count ? Data(payload[tcp.dataOffset...]) : Data()
        case .udp:
            return payload.count > 8 ? Data(payload[8...]) : Data()
        case .icmp:
            return payload.count > 8 ? Data(payload[8...]) : Data()
        default:
            return payload
        }
    }
}

// MARK: - IP Protocol Number

public enum IPProtocol: UInt8 {
    case icmp = 1
    case tcp = 6
    case udp = 17
    case icmpv6 = 58
    case unknown = 255

    public var name: String {
        switch self {
        case .icmp: return "ICMP"
        case .tcp: return "TCP"
        case .udp: return "UDP"
        case .icmpv6: return "ICMPv6"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - TCP Header

public struct TCPHeader {
    public let sourcePort: UInt16
    public let destinationPort: UInt16
    public let sequenceNumber: UInt32
    public let ackNumber: UInt32
    public let dataOffset: Int          // in bytes
    public let flags: UInt8
    public let windowSize: UInt16

    public var isSYN: Bool { flags & 0x02 != 0 }
    public var isACK: Bool { flags & 0x10 != 0 }
    public var isFIN: Bool { flags & 0x01 != 0 }
    public var isRST: Bool { flags & 0x04 != 0 }
    public var isPSH: Bool { flags & 0x08 != 0 }

    public var flagsDescription: String {
        var f = [String]()
        if isSYN { f.append("SYN") }
        if isACK { f.append("ACK") }
        if isFIN { f.append("FIN") }
        if isRST { f.append("RST") }
        if isPSH { f.append("PSH") }
        return f.isEmpty ? "NONE" : f.joined(separator: "|")
    }
}

// MARK: - UDP Header

public struct UDPHeader {
    public let sourcePort: UInt16
    public let destinationPort: UInt16
    public let length: UInt16
    public let checksum: UInt16

    /// Well-known UDP port identification
    public var knownProtocol: String? {
        switch destinationPort {
        case 53: return "DNS"
        case 123: return "NTP"
        case 443: return "QUIC"
        case 5353: return "mDNS"
        case 67, 68: return "DHCP"
        case 1900: return "SSDP"
        case 5060: return "SIP"
        default:
            switch sourcePort {
            case 53: return "DNS"
            case 123: return "NTP"
            case 443: return "QUIC"
            default: return nil
            }
        }
    }
}

// MARK: - ICMP Header

public struct ICMPHeader {
    public let type: UInt8
    public let code: UInt8
    public let checksum: UInt16
    public let identifier: UInt16
    public let sequenceNumber: UInt16

    public var typeName: String {
        switch type {
        case 0: return "Echo Reply"
        case 3: return "Destination Unreachable"
        case 8: return "Echo Request"
        case 11: return "Time Exceeded"
        default: return "Type \(type)"
        }
    }
}

// MARK: - Parser

public class IPPacketParser {

    /// Parse a raw IP packet (as received from packetFlow.readPackets).
    public static func parse(_ data: Data) -> IPPacket? {
        guard data.count >= 20 else { return nil }

        let version = (data[0] >> 4) & 0x0F

        switch version {
        case 4: return parseIPv4(data)
        case 6: return parseIPv6(data)
        default: return nil
        }
    }

    // MARK: - IPv4

    private static func parseIPv4(_ data: Data) -> IPPacket? {
        guard data.count >= 20 else { return nil }

        let ihl = Int(data[0] & 0x0F) * 4  // header length in bytes
        guard data.count >= ihl else { return nil }

        let totalLength = Int(readUInt16(data, at: 2))
        let ttl = data[8]
        let protoRaw = data[9]
        let proto = IPProtocol(rawValue: protoRaw) ?? .unknown

        let srcIP = "\(data[12]).\(data[13]).\(data[14]).\(data[15])"
        let dstIP = "\(data[16]).\(data[17]).\(data[18]).\(data[19])"

        let payload = data.count > ihl ? Data(data[ihl...]) : Data()

        var packet = IPPacket(
            version: 4, proto: proto,
            sourceIP: srcIP, destinationIP: dstIP,
            totalLength: totalLength, ttl: ttl,
            headerLength: ihl, payload: payload
        )

        // Parse transport header
        switch proto {
        case .tcp: packet.tcpHeader = parseTCPHeader(payload)
        case .udp: packet.udpHeader = parseUDPHeader(payload)
        case .icmp: packet.icmpHeader = parseICMPHeader(payload)
        default: break
        }

        return packet
    }

    // MARK: - IPv6

    private static func parseIPv6(_ data: Data) -> IPPacket? {
        guard data.count >= 40 else { return nil }

        let payloadLength = Int(readUInt16(data, at: 4))
        let nextHeader = data[6]
        let hopLimit = data[7]
        let proto = IPProtocol(rawValue: nextHeader) ?? .unknown

        // Source address (16 bytes at offset 8)
        let srcIP = formatIPv6(data, offset: 8)
        let dstIP = formatIPv6(data, offset: 24)

        let payload = data.count > 40 ? Data(data[40...]) : Data()

        var packet = IPPacket(
            version: 6, proto: proto,
            sourceIP: srcIP, destinationIP: dstIP,
            totalLength: 40 + payloadLength, ttl: hopLimit,
            headerLength: 40, payload: payload
        )

        switch proto {
        case .tcp: packet.tcpHeader = parseTCPHeader(payload)
        case .udp: packet.udpHeader = parseUDPHeader(payload)
        case .icmpv6, .icmp: packet.icmpHeader = parseICMPHeader(payload)
        default: break
        }

        return packet
    }

    // MARK: - TCP Header

    private static func parseTCPHeader(_ data: Data) -> TCPHeader? {
        guard data.count >= 20 else { return nil }
        let srcPort = readUInt16(data, at: 0)
        let dstPort = readUInt16(data, at: 2)
        let seq = readUInt32(data, at: 4)
        let ack = readUInt32(data, at: 8)
        let dataOffsetByte = data[12]
        let dataOffset = Int((dataOffsetByte >> 4) & 0x0F) * 4
        let flags = data[13]
        let window = readUInt16(data, at: 14)

        return TCPHeader(
            sourcePort: srcPort, destinationPort: dstPort,
            sequenceNumber: seq, ackNumber: ack,
            dataOffset: dataOffset, flags: flags, windowSize: window
        )
    }

    // MARK: - UDP Header

    private static func parseUDPHeader(_ data: Data) -> UDPHeader? {
        guard data.count >= 8 else { return nil }
        return UDPHeader(
            sourcePort: readUInt16(data, at: 0),
            destinationPort: readUInt16(data, at: 2),
            length: readUInt16(data, at: 4),
            checksum: readUInt16(data, at: 6)
        )
    }

    // MARK: - ICMP Header

    private static func parseICMPHeader(_ data: Data) -> ICMPHeader? {
        guard data.count >= 8 else { return nil }
        return ICMPHeader(
            type: data[0], code: data[1],
            checksum: readUInt16(data, at: 2),
            identifier: readUInt16(data, at: 4),
            sequenceNumber: readUInt16(data, at: 6)
        )
    }

    // MARK: - Format

    /// Format packet as one-line summary for logging.
    public static func format(_ packet: IPPacket) -> String {
        switch packet.proto {
        case .tcp:
            guard let tcp = packet.tcpHeader else { return "TCP ?" }
            let appBytes = packet.applicationData.count
            return "TCP \(packet.sourceIP):\(tcp.sourcePort) → \(packet.destinationIP):\(tcp.destinationPort) [\(tcp.flagsDescription)] \(appBytes)B"
        case .udp:
            guard let udp = packet.udpHeader else { return "UDP ?" }
            let proto = udp.knownProtocol.map { " (\($0))" } ?? ""
            return "UDP \(packet.sourceIP):\(udp.sourcePort) → \(packet.destinationIP):\(udp.destinationPort)\(proto) \(udp.length)B"
        case .icmp, .icmpv6:
            guard let icmp = packet.icmpHeader else { return "ICMP ?" }
            return "ICMP \(packet.sourceIP) → \(packet.destinationIP) \(icmp.typeName)"
        default:
            return "IP(\(packet.proto.rawValue)) \(packet.sourceIP) → \(packet.destinationIP) \(packet.totalLength)B"
        }
    }

    // MARK: - Helpers

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 |
        UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])
    }

    private static func formatIPv6(_ data: Data, offset: Int) -> String {
        var parts = [String]()
        for i in stride(from: 0, to: 16, by: 2) {
            parts.append(String(format: "%02x%02x", data[offset + i], data[offset + i + 1]))
        }
        return parts.joined(separator: ":")
    }
}
