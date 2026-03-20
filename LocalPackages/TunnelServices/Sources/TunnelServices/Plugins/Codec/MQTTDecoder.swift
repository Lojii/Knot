//
//  MQTTDecoder.swift
//  TunnelServices
//
//  MQTT protocol decoder (v3.1.1 / v5.0).
//
//  Netty reference: codec-mqtt/MqttDecoder.java, MqttEncoder.java
//

import Foundation

// MARK: - MQTT Packet

public struct MQTTPacket {
    public let type: PacketType
    public let flags: UInt8
    public let payload: Data

    // CONNECT fields
    public var clientID: String?
    public var username: String?
    public var protocolName: String?
    public var protocolLevel: UInt8?

    // PUBLISH fields
    public var topic: String?
    public var messagePayload: Data?
    public var qos: Int?
    public var retain: Bool?
    public var packetID: UInt16?

    // SUBSCRIBE fields
    public var subscriptions: [(topic: String, qos: Int)]?

    public enum PacketType: UInt8, CustomStringConvertible {
        case connect     = 1
        case connack     = 2
        case publish     = 3
        case puback      = 4
        case pubrec      = 5
        case pubrel      = 6
        case pubcomp     = 7
        case subscribe   = 8
        case suback      = 9
        case unsubscribe = 10
        case unsuback    = 11
        case pingreq     = 12
        case pingresp    = 13
        case disconnect  = 14
        case auth        = 15

        public var description: String {
            switch self {
            case .connect: return "CONNECT"
            case .connack: return "CONNACK"
            case .publish: return "PUBLISH"
            case .puback: return "PUBACK"
            case .pubrec: return "PUBREC"
            case .pubrel: return "PUBREL"
            case .pubcomp: return "PUBCOMP"
            case .subscribe: return "SUBSCRIBE"
            case .suback: return "SUBACK"
            case .unsubscribe: return "UNSUBSCRIBE"
            case .unsuback: return "UNSUBACK"
            case .pingreq: return "PINGREQ"
            case .pingresp: return "PINGRESP"
            case .disconnect: return "DISCONNECT"
            case .auth: return "AUTH"
            }
        }
    }
}

// MARK: - MQTT Parser

public class MQTTParser {

    /// Parse MQTT packets from raw TCP data.
    public static func parse(_ data: Data) -> [MQTTPacket] {
        var packets = [MQTTPacket]()
        var offset = 0

        while offset < data.count {
            guard offset + 2 <= data.count else { break }

            let firstByte = data[offset]
            let typeRaw = (firstByte >> 4) & 0x0F
            let flags = firstByte & 0x0F
            offset += 1

            guard let type = MQTTPacket.PacketType(rawValue: typeRaw) else { break }
            guard let (remainingLength, lenBytes) = decodeRemainingLength(data, at: offset) else { break }
            offset += lenBytes

            guard offset + remainingLength <= data.count else { break }
            let payload = Data(data[offset..<(offset + remainingLength)])
            offset += remainingLength

            var packet = MQTTPacket(type: type, flags: flags, payload: payload)

            // Parse specific packet types
            switch type {
            case .connect:
                parseConnect(&packet, payload: payload)
            case .publish:
                parsePublish(&packet, payload: payload, flags: flags)
            case .subscribe:
                parseSubscribe(&packet, payload: payload)
            default:
                break
            }

            packets.append(packet)
        }

        return packets
    }

    /// Format MQTT packet as readable text.
    public static func format(_ packet: MQTTPacket) -> String {
        var parts = ["[\(packet.type)]"]

        switch packet.type {
        case .connect:
            if let proto = packet.protocolName { parts.append("proto=\(proto)") }
            if let clientID = packet.clientID { parts.append("client=\(clientID)") }
            if let user = packet.username { parts.append("user=\(user)") }
        case .publish:
            if let topic = packet.topic { parts.append("topic=\(topic)") }
            if let qos = packet.qos { parts.append("qos=\(qos)") }
            if let retain = packet.retain, retain { parts.append("retain") }
            if let msg = packet.messagePayload {
                let preview = String(data: msg.prefix(200), encoding: .utf8) ?? "[\(msg.count)B]"
                parts.append("payload=\"\(preview)\"")
            }
        case .subscribe:
            if let subs = packet.subscriptions {
                for sub in subs { parts.append("\(sub.topic)(qos=\(sub.qos))") }
            }
        case .pingreq: parts.append("ping")
        case .pingresp: parts.append("pong")
        case .disconnect: parts.append("bye")
        default: break
        }

        return parts.joined(separator: " ")
    }

    /// Detect MQTT by checking the first bytes of a TCP stream.
    public static func isMQTT(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        let type = (data[0] >> 4) & 0x0F
        if type != 1 { return false }  // First packet must be CONNECT
        // Check for "MQTT" or "MQIsdp" protocol name
        guard data.count >= 10 else { return false }
        guard let (_, lenBytes) = decodeRemainingLength(data, at: 1) else { return false }
        let nameStart = 1 + lenBytes + 2  // skip fixed header + length field + name length
        guard nameStart + 4 <= data.count else { return false }
        let name = String(data: data[nameStart..<(nameStart + 4)], encoding: .utf8)
        return name == "MQTT" || name == "MQIs"
    }

    // MARK: - Specific Parsers

    private static func parseConnect(_ packet: inout MQTTPacket, payload: Data) {
        var off = 0
        guard let protoName = readMQTTString(payload, at: &off) else { return }
        packet.protocolName = protoName
        guard off < payload.count else { return }
        packet.protocolLevel = payload[off]; off += 1
        guard off < payload.count else { return }
        let connectFlags = payload[off]; off += 1
        off += 2  // keepalive
        // Client ID
        packet.clientID = readMQTTString(payload, at: &off)
        // Username (if flag set)
        if connectFlags & 0x80 != 0 { packet.username = readMQTTString(payload, at: &off) }
    }

    private static func parsePublish(_ packet: inout MQTTPacket, payload: Data, flags: UInt8) {
        var off = 0
        packet.topic = readMQTTString(payload, at: &off)
        packet.qos = Int((flags >> 1) & 0x03)
        packet.retain = (flags & 0x01) != 0
        if packet.qos! > 0 {
            guard off + 2 <= payload.count else { return }
            packet.packetID = UInt16(payload[off]) << 8 | UInt16(payload[off + 1])
            off += 2
        }
        if off < payload.count {
            packet.messagePayload = Data(payload[off...])
        }
    }

    private static func parseSubscribe(_ packet: inout MQTTPacket, payload: Data) {
        var off = 2  // skip packet ID
        var subs = [(String, Int)]()
        while off < payload.count {
            guard let topic = readMQTTString(payload, at: &off) else { break }
            guard off < payload.count else { break }
            let qos = Int(payload[off] & 0x03); off += 1
            subs.append((topic, qos))
        }
        packet.subscriptions = subs
    }

    // MARK: - Helpers

    private static func decodeRemainingLength(_ data: Data, at offset: Int) -> (Int, Int)? {
        var multiplier = 1
        var value = 0
        var pos = offset
        repeat {
            guard pos < data.count else { return nil }
            let byte = Int(data[pos])
            value += (byte & 127) * multiplier
            multiplier *= 128
            pos += 1
            if multiplier > 128 * 128 * 128 * 128 { return nil }
            if byte & 128 == 0 { return (value, pos - offset) }
        } while true
    }

    private static func readMQTTString(_ data: Data, at offset: inout Int) -> String? {
        guard offset + 2 <= data.count else { return nil }
        let length = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2
        guard offset + length <= data.count else { return nil }
        let str = String(data: data[offset..<(offset + length)], encoding: .utf8)
        offset += length
        return str
    }
}
