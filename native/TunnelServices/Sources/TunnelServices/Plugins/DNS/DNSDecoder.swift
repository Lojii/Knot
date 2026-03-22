//
//  DNSDecoder.swift
//  TunnelServices
//
//  DNS wire format decoder for DoH (DNS over HTTPS) capture.
//  Detects content-type: application/dns-message and parses the DNS packet.
//
//  Netty reference: codec-dns/DatagramDnsQueryDecoder.java, DnsRecordType.java
//

import Foundation

// MARK: - DNS Message

public struct DNSMessage {
    public let id: UInt16
    public let isResponse: Bool
    public let opcode: UInt8
    public let responseCode: ResponseCode
    public let questions: [Question]
    public let answers: [ResourceRecord]
    public let authorities: [ResourceRecord]
    public let additionals: [ResourceRecord]

    public struct Question {
        public let name: String
        public let type: RecordType
        public let classCode: UInt16
    }

    public struct ResourceRecord {
        public let name: String
        public let type: RecordType
        public let classCode: UInt16
        public let ttl: UInt32
        public let data: String
    }

    public enum ResponseCode: UInt8 {
        case noError = 0, formatError = 1, serverFailure = 2
        case nameError = 3, notImplemented = 4, refused = 5
        case unknown = 255
    }

    public enum RecordType: UInt16 {
        case A = 1, NS = 2, CNAME = 5, SOA = 6, PTR = 12
        case MX = 15, TXT = 16, AAAA = 28, SRV = 33, HTTPS = 65
        case unknown = 0

        public var name: String {
            switch self {
            case .A: return "A"
            case .NS: return "NS"
            case .CNAME: return "CNAME"
            case .SOA: return "SOA"
            case .PTR: return "PTR"
            case .MX: return "MX"
            case .TXT: return "TXT"
            case .AAAA: return "AAAA"
            case .SRV: return "SRV"
            case .HTTPS: return "HTTPS"
            case .unknown: return "UNKNOWN"
            }
        }
    }
}

// MARK: - DNS Parser

public class DNSParser {

    public static func parse(_ data: Data) -> DNSMessage? {
        guard data.count >= 12 else { return nil }
        var offset = 0

        let id = readUInt16(data, at: &offset)
        let flags = readUInt16(data, at: &offset)
        let qdCount = readUInt16(data, at: &offset)
        let anCount = readUInt16(data, at: &offset)
        let nsCount = readUInt16(data, at: &offset)
        let arCount = readUInt16(data, at: &offset)

        let isResponse = (flags & 0x8000) != 0
        let opcode = UInt8((flags >> 11) & 0x0F)
        let rcode = DNSMessage.ResponseCode(rawValue: UInt8(flags & 0x0F)) ?? .unknown

        var questions = [DNSMessage.Question]()
        for _ in 0..<qdCount {
            guard let name = readName(data, at: &offset) else { break }
            guard offset + 4 <= data.count else { break }
            let type = readUInt16(data, at: &offset)
            let classCode = readUInt16(data, at: &offset)
            questions.append(DNSMessage.Question(
                name: name,
                type: DNSMessage.RecordType(rawValue: type) ?? .unknown,
                classCode: classCode
            ))
        }

        let answers = parseRecords(data, count: Int(anCount), offset: &offset)
        let authorities = parseRecords(data, count: Int(nsCount), offset: &offset)
        let additionals = parseRecords(data, count: Int(arCount), offset: &offset)

        return DNSMessage(
            id: id, isResponse: isResponse, opcode: opcode,
            responseCode: rcode, questions: questions,
            answers: answers, authorities: authorities, additionals: additionals
        )
    }

    /// Format DNS message as readable text for session recording.
    public static func format(_ msg: DNSMessage) -> String {
        var lines = [String]()
        lines.append("[DNS \(msg.isResponse ? "Response" : "Query")] id=\(msg.id) rcode=\(msg.responseCode)")

        for q in msg.questions {
            lines.append("  Q: \(q.name) \(q.type.name)")
        }
        for a in msg.answers {
            lines.append("  A: \(a.name) \(a.type.name) TTL=\(a.ttl) → \(a.data)")
        }
        for a in msg.authorities {
            lines.append("  NS: \(a.name) \(a.type.name) → \(a.data)")
        }
        return lines.joined(separator: "\n")
    }

    /// Check if HTTP content is DNS over HTTPS.
    public static func isDNSOverHTTPS(contentType: String?, uri: String?) -> Bool {
        if contentType == "application/dns-message" { return true }
        if let uri = uri, uri.contains("/dns-query") { return true }
        return false
    }

    // MARK: - Wire Format Helpers

    private static func parseRecords(_ data: Data, count: Int, offset: inout Int) -> [DNSMessage.ResourceRecord] {
        var records = [DNSMessage.ResourceRecord]()
        for _ in 0..<count {
            guard let name = readName(data, at: &offset) else { break }
            guard offset + 10 <= data.count else { break }
            let type = readUInt16(data, at: &offset)
            let classCode = readUInt16(data, at: &offset)
            let ttl = readUInt32(data, at: &offset)
            let rdLength = Int(readUInt16(data, at: &offset))
            guard offset + rdLength <= data.count else { break }

            let rdata = parseRData(data, type: type, offset: offset, length: rdLength)
            offset += rdLength

            records.append(DNSMessage.ResourceRecord(
                name: name,
                type: DNSMessage.RecordType(rawValue: type) ?? .unknown,
                classCode: classCode, ttl: ttl, data: rdata
            ))
        }
        return records
    }

    private static func parseRData(_ data: Data, type: UInt16, offset: Int, length: Int) -> String {
        switch type {
        case 1: // A record (IPv4)
            guard length == 4 else { return "<invalid>" }
            return "\(data[offset]).\(data[offset+1]).\(data[offset+2]).\(data[offset+3])"
        case 28: // AAAA record (IPv6)
            guard length == 16 else { return "<invalid>" }
            var parts = [String]()
            for i in stride(from: 0, to: 16, by: 2) {
                parts.append(String(format: "%02x%02x", data[offset+i], data[offset+i+1]))
            }
            return parts.joined(separator: ":")
        case 5, 2, 12: // CNAME, NS, PTR
            var off = offset
            return readName(data, at: &off) ?? "<invalid>"
        default:
            if let str = String(data: data[offset..<(offset+length)], encoding: .utf8) { return str }
            return "<\(length) bytes>"
        }
    }

    private static func readName(_ data: Data, at offset: inout Int) -> String? {
        var labels = [String]()
        var jumped = false
        var jumpOffset = 0

        while offset < data.count {
            let len = Int(data[offset])
            if len == 0 { offset += 1; break }

            if len & 0xC0 == 0xC0 {
                if !jumped { jumpOffset = offset + 2 }
                guard offset + 1 < data.count else { return nil }
                offset = Int(data[offset] & 0x3F) << 8 | Int(data[offset + 1])
                jumped = true
                continue
            }

            offset += 1
            guard offset + len <= data.count else { return nil }
            if let label = String(data: data[offset..<(offset+len)], encoding: .utf8) {
                labels.append(label)
            }
            offset += len
        }

        if jumped { offset = jumpOffset }
        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }

    private static func readUInt16(_ data: Data, at offset: inout Int) -> UInt16 {
        let value = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        offset += 2
        return value
    }

    private static func readUInt32(_ data: Data, at offset: inout Int) -> UInt32 {
        let value = UInt32(data[offset]) << 24 | UInt32(data[offset+1]) << 16 | UInt32(data[offset+2]) << 8 | UInt32(data[offset+3])
        offset += 4
        return value
    }
}
