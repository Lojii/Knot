//
//  NTPDecoder.swift
//  TunnelServices
//
//  NTP (Network Time Protocol) packet decoder.
//  NTP uses UDP port 123, packet is always 48 bytes.
//

import Foundation

public struct NTPPacket {
    public let leapIndicator: UInt8    // 0=no warning, 1=+1s, 2=-1s, 3=alarm
    public let version: UInt8          // 3 or 4
    public let mode: Mode
    public let stratum: UInt8          // 0=unspecified, 1=primary, 2-15=secondary
    public let pollInterval: Int8
    public let precision: Int8
    public let rootDelay: Double       // seconds
    public let rootDispersion: Double  // seconds
    public let referenceID: String
    public let referenceTime: Date?
    public let originTime: Date?
    public let receiveTime: Date?
    public let transmitTime: Date?

    public enum Mode: UInt8 {
        case reserved = 0, symmetricActive = 1, symmetricPassive = 2
        case client = 3, server = 4, broadcast = 5, control = 6, privateUse = 7
        public var name: String {
            switch self {
            case .client: return "Client"
            case .server: return "Server"
            case .broadcast: return "Broadcast"
            default: return "Mode(\(rawValue))"
            }
        }
    }
}

public class NTPDecoder {

    /// Parse NTP packet (48 bytes minimum).
    public static func parse(_ data: Data) -> NTPPacket? {
        guard data.count >= 48 else { return nil }

        let li = (data[0] >> 6) & 0x03
        let version = (data[0] >> 3) & 0x07
        let mode = NTPPacket.Mode(rawValue: data[0] & 0x07) ?? .reserved
        let stratum = data[1]
        let poll = Int8(bitPattern: data[2])
        let precision = Int8(bitPattern: data[3])

        let rootDelay = ntpShortToDouble(data, at: 4)
        let rootDispersion = ntpShortToDouble(data, at: 8)

        let refID: String
        if stratum <= 1 {
            // ASCII reference identifier
            refID = String(data: data[12..<16], encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? ""
        } else {
            // IPv4 address or hash
            refID = "\(data[12]).\(data[13]).\(data[14]).\(data[15])"
        }

        return NTPPacket(
            leapIndicator: li, version: version, mode: mode,
            stratum: stratum, pollInterval: poll, precision: precision,
            rootDelay: rootDelay, rootDispersion: rootDispersion,
            referenceID: refID,
            referenceTime: ntpTimestampToDate(data, at: 16),
            originTime: ntpTimestampToDate(data, at: 24),
            receiveTime: ntpTimestampToDate(data, at: 32),
            transmitTime: ntpTimestampToDate(data, at: 40)
        )
    }

    public static func format(_ packet: NTPPacket) -> String {
        var parts = ["[NTP v\(packet.version)]", packet.mode.name]
        parts.append("stratum=\(packet.stratum)")
        if !packet.referenceID.isEmpty { parts.append("ref=\(packet.referenceID)") }
        if let tx = packet.transmitTime {
            let formatter = ISO8601DateFormatter()
            parts.append("tx=\(formatter.string(from: tx))")
        }
        parts.append("delay=\(String(format: "%.3f", packet.rootDelay))s")
        return parts.joined(separator: " ")
    }

    // MARK: - NTP Timestamp Conversion

    /// NTP timestamp: 32-bit seconds since 1900-01-01 + 32-bit fraction
    private static let ntpEpochOffset: TimeInterval = 2208988800  // seconds between 1900 and 1970

    private static func ntpTimestampToDate(_ data: Data, at offset: Int) -> Date? {
        let seconds = readUInt32(data, at: offset)
        guard seconds > 0 else { return nil }
        let fraction = readUInt32(data, at: offset + 4)
        let interval = Double(seconds) - ntpEpochOffset + Double(fraction) / 4294967296.0
        return Date(timeIntervalSince1970: interval)
    }

    private static func ntpShortToDouble(_ data: Data, at offset: Int) -> Double {
        let value = readUInt32(data, at: offset)
        return Double(value) / 65536.0
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 |
        UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])
    }
}
