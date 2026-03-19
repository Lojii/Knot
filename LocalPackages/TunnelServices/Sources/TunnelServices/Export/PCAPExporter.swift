//
//  PCAPExporter.swift
//  TunnelServices
//
//  Exports captured sessions as standard .pcap files (Wireshark compatible).
//  Implements the pcap file format from scratch (no external dependency).
//
//  Reference: https://wiki.wireshark.org/Development/LibpcapFileFormat
//  Netty reference: handler/pcap/PcapWriter.java, PcapHeaders.java
//

import Foundation
import NIO

// MARK: - PCAP File Writer

public class PCAPWriter {
    private let fileHandle: FileHandle
    private var packetCount = 0

    /// Create a new pcap file at the given path.
    public init(filePath: String) throws {
        FileManager.default.createFile(atPath: filePath, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: filePath) else {
            throw PCAPError.cannotCreateFile(filePath)
        }
        self.fileHandle = handle
        writeGlobalHeader()
    }

    deinit {
        fileHandle.closeFile()
    }

    // MARK: - Global Header

    /// pcap global header (24 bytes)
    private func writeGlobalHeader() {
        var header = Data(capacity: 24)
        header.appendUInt32(0xa1b2c3d4)   // magic number (native byte order)
        header.appendUInt16(2)              // version major
        header.appendUInt16(4)              // version minor
        header.appendInt32(0)               // thiszone (GMT)
        header.appendUInt32(0)              // sigfigs
        header.appendUInt32(65535)          // snaplen
        header.appendUInt32(228)            // network: LINKTYPE_RAW (raw IPv4/IPv6)
        fileHandle.write(header)
    }

    // MARK: - Write Packets

    /// Write a TCP packet to the pcap file.
    public func writeTCPPacket(
        timestamp: Date,
        srcIP: String, srcPort: UInt16,
        dstIP: String, dstPort: UInt16,
        payload: Data,
        flags: TCPFlags = .ack
    ) {
        let tcpHeader = buildTCPHeader(srcPort: srcPort, dstPort: dstPort, flags: flags, payloadLength: payload.count)
        let ipPacket = buildIPv4Packet(srcIP: srcIP, dstIP: dstIP, protocol: 6, payload: tcpHeader + payload)
        writePacketRecord(timestamp: timestamp, data: ipPacket)
    }

    /// Write a UDP packet to the pcap file.
    public func writeUDPPacket(
        timestamp: Date,
        srcIP: String, srcPort: UInt16,
        dstIP: String, dstPort: UInt16,
        payload: Data
    ) {
        let udpHeader = buildUDPHeader(srcPort: srcPort, dstPort: dstPort, payloadLength: payload.count)
        let ipPacket = buildIPv4Packet(srcIP: srcIP, dstIP: dstIP, protocol: 17, payload: udpHeader + payload)
        writePacketRecord(timestamp: timestamp, data: ipPacket)
    }

    /// Write raw packet record (header + data).
    private func writePacketRecord(timestamp: Date, data: Data) {
        let ts = timestamp.timeIntervalSince1970
        let tsSec = UInt32(ts)
        let tsUsec = UInt32((ts - Double(tsSec)) * 1_000_000)
        let len = UInt32(data.count)

        var record = Data(capacity: 16 + data.count)
        record.appendUInt32(tsSec)      // ts_sec
        record.appendUInt32(tsUsec)     // ts_usec
        record.appendUInt32(len)        // incl_len
        record.appendUInt32(len)        // orig_len
        record.append(data)
        fileHandle.write(record)
        packetCount += 1
    }

    public func close() {
        fileHandle.closeFile()
    }

    public var count: Int { packetCount }

    // MARK: - IPv4 Header (20 bytes)

    private func buildIPv4Packet(srcIP: String, dstIP: String, protocol proto: UInt8, payload: Data) -> Data {
        let totalLength = UInt16(20 + payload.count)
        var header = Data(capacity: 20 + payload.count)
        header.append(0x45)                         // version(4) + IHL(5)
        header.append(0x00)                         // DSCP + ECN
        header.appendUInt16(totalLength)            // total length
        header.appendUInt16(0x0000)                 // identification
        header.appendUInt16(0x4000)                 // flags(Don't Fragment) + fragment offset
        header.append(64)                           // TTL
        header.append(proto)                        // protocol (6=TCP, 17=UDP)
        header.appendUInt16(0x0000)                 // checksum (0 = let Wireshark recalculate)
        header.append(contentsOf: parseIPv4(srcIP)) // source IP
        header.append(contentsOf: parseIPv4(dstIP)) // destination IP
        header.append(payload)
        return header
    }

    // MARK: - TCP Header (20 bytes)

    private func buildTCPHeader(srcPort: UInt16, dstPort: UInt16, flags: TCPFlags, payloadLength: Int) -> Data {
        var header = Data(capacity: 20)
        header.appendUInt16(srcPort)      // source port
        header.appendUInt16(dstPort)      // destination port
        header.appendUInt32(0)            // sequence number
        header.appendUInt32(0)            // acknowledgment number
        header.appendUInt16(0x5000 | UInt16(flags.rawValue))  // data offset(5) + flags
        header.appendUInt16(65535)        // window size
        header.appendUInt16(0x0000)       // checksum
        header.appendUInt16(0x0000)       // urgent pointer
        return header
    }

    // MARK: - UDP Header (8 bytes)

    private func buildUDPHeader(srcPort: UInt16, dstPort: UInt16, payloadLength: Int) -> Data {
        let length = UInt16(8 + payloadLength)
        var header = Data(capacity: 8)
        header.appendUInt16(srcPort)
        header.appendUInt16(dstPort)
        header.appendUInt16(length)
        header.appendUInt16(0x0000)  // checksum
        return header
    }

    // MARK: - Helpers

    private func parseIPv4(_ ip: String) -> [UInt8] {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        return parts.count == 4 ? parts : [127, 0, 0, 1]
    }
}

// MARK: - TCP Flags

public struct TCPFlags: OptionSet {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let fin = TCPFlags(rawValue: 0x01)
    public static let syn = TCPFlags(rawValue: 0x02)
    public static let rst = TCPFlags(rawValue: 0x04)
    public static let psh = TCPFlags(rawValue: 0x08)
    public static let ack = TCPFlags(rawValue: 0x10)
}

// MARK: - FlowRecord Export

public class PCAPExporter {

    /// Export a list of FlowRecords to a .pcap file.
    public static func export(flows: [FlowRecord], to filePath: String) throws -> Int {
        let writer = try PCAPWriter(filePath: filePath)
        defer { writer.close() }

        for flow in flows {
            exportFlow(flow, writer: writer)
        }
        return writer.count
    }

    /// Export a single FlowRecord as TCP packets.
    private static func exportFlow(_ flow: FlowRecord, writer: PCAPWriter) {
        // Extract IPs from metadata, fall back to defaults
        let srcIP = (flow.metadata["localAddress"] as? String)?.components(separatedBy: ":").first ?? "127.0.0.1"
        let dstIP = (flow.metadata["remoteAddress"] as? String)?.components(separatedBy: ":").first ?? "0.0.0.0"
        let dstPort = UInt16(flow.port)
        let srcPort = UInt16.random(in: 49152...65535)

        let startTime = Date(timeIntervalSince1970: flow.startedAt)

        // Request header line from metadata or synthesize from search keys
        let reqLine = (flow.metadata["reqLine"] as? String)
            ?? "\(flow.searchKey1) \(flow.searchKey2) HTTP/1.1\r\nHost: \(flow.host)\r\n\r\n"
        if let reqHeadData = reqLine.data(using: .utf8) {
            writer.writeTCPPacket(
                timestamp: startTime,
                srcIP: srcIP, srcPort: srcPort,
                dstIP: dstIP, dstPort: dstPort,
                payload: reqHeadData,
                flags: [.psh, .ack]
            )
        }

        // Request body
        if !flow.reqPayloadRef.isEmpty, let reqBodyData = readSessionFile(flow.reqPayloadRef) {
            let ts = Date(timeIntervalSince1970: flow.reqEndAt ?? flow.startedAt)
            writer.writeTCPPacket(
                timestamp: ts,
                srcIP: srcIP, srcPort: srcPort,
                dstIP: dstIP, dstPort: dstPort,
                payload: reqBodyData,
                flags: [.psh, .ack]
            )
        }

        // Response status line
        let httpVersion = (flow.metadata["rspHttpVersion"] as? String) ?? "HTTP/1.1"
        let statusCode = flow.searchKey3.isEmpty ? "200" : flow.searchKey3
        let statusMessage = (flow.metadata["rspMessage"] as? String) ?? "OK"
        if let rspLine = "\(httpVersion) \(statusCode) \(statusMessage)".data(using: .utf8) {
            let ts = Date(timeIntervalSince1970: flow.rspStartAt ?? flow.startedAt)
            writer.writeTCPPacket(
                timestamp: ts,
                srcIP: dstIP, srcPort: dstPort,
                dstIP: srcIP, dstPort: srcPort,
                payload: rspLine,
                flags: [.psh, .ack]
            )
        }

        // Response body
        if !flow.rspPayloadRef.isEmpty, let rspBodyData = readSessionFile(flow.rspPayloadRef) {
            let ts = Date(timeIntervalSince1970: flow.endedAt ?? flow.startedAt)
            writer.writeTCPPacket(
                timestamp: ts,
                srcIP: dstIP, srcPort: dstPort,
                dstIP: srcIP, dstPort: srcPort,
                payload: rspBodyData,
                flags: [.psh, .ack]
            )
        }
    }

    private static func readSessionFile(_ path: String) -> Data? {
        guard !path.isEmpty else { return nil }
        return FileManager.default.contents(atPath: path)
    }
}

// MARK: - PCAP Error

public enum PCAPError: Error, LocalizedError {
    case cannotCreateFile(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let path): return "Cannot create pcap file at \(path)"
        }
    }
}

// MARK: - Data Helpers (Big Endian)

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.bigEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
    mutating func appendUInt32(_ value: UInt32) {
        var v = value.bigEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
    mutating func appendInt32(_ value: Int32) {
        var v = value.bigEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}
