//
//  TLSSniffHandler.swift
//  TunnelServices
//
//  Passively sniffs TLS handshake messages without modifying them.
//  Extracts SNI, TLS version, cipher suites, ALPN, and server certificate
//  from the ClientHello and ServerHello as they pass through the tunnel.
//  Removes itself after the handshake phase completes.
//

import Foundation
import NIO

/// Sniffs the client→server direction (ClientHello).
public final class TLSClientSniffHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    private let recorder: SessionRecorder
    private var done = false

    public init(recorder: SessionRecorder) {
        self.recorder = recorder
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if !done {
            let buffer = unwrapInboundIn(data)
            parseClientHello(buffer)
            done = true
            // Remove ourselves — only need the first message
            context.pipeline.removeHandler(self, promise: nil)
        }
        // Always forward data through
        context.fireChannelRead(data)
    }

    private func parseClientHello(_ buffer: ByteBuffer) {
        // TLS record: type(1) + version(2) + length(2) + handshake
        guard buffer.readableBytes >= 5 else { return }
        let b0 = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) ?? 0
        guard b0 == 22 else { return } // ContentType.Handshake

        let recordVersion = TLSSniffUtils.readVersion(buffer, offset: buffer.readerIndex + 1)

        // Handshake header: type(1) + length(3)
        let hsOffset = buffer.readerIndex + 5
        guard buffer.readableBytes > 9 else { return }
        let hsType = buffer.getInteger(at: hsOffset, as: UInt8.self) ?? 0
        guard hsType == 1 else { return } // ClientHello

        // ClientHello: version(2) + random(32) + sessionId(var) + cipherSuites(var) + ...
        let chOffset = hsOffset + 4
        guard buffer.readableBytes > chOffset - buffer.readerIndex + 34 else { return }

        let clientVersion = TLSSniffUtils.readVersion(buffer, offset: chOffset)

        // Skip: version(2) + random(32) + sessionIdLen(1) + sessionId
        var pos = chOffset + 34
        guard pos < buffer.readerIndex + buffer.readableBytes else { return }
        let sessionIdLen = Int(buffer.getInteger(at: pos, as: UInt8.self) ?? 0)
        pos += 1 + sessionIdLen

        // Cipher suites
        guard pos + 2 <= buffer.readerIndex + buffer.readableBytes else { return }
        let cipherSuitesLen = Int(buffer.getInteger(at: pos, as: UInt16.self) ?? 0)
        var cipherSuites = [UInt16]()
        let csEnd = pos + 2 + cipherSuitesLen
        var csPos = pos + 2
        while csPos + 1 < csEnd && csPos + 1 < buffer.readerIndex + buffer.readableBytes {
            if let cs = buffer.getInteger(at: csPos, as: UInt16.self) {
                cipherSuites.append(cs)
            }
            csPos += 2
        }
        pos = csEnd

        // Skip compression methods
        guard pos + 1 <= buffer.readerIndex + buffer.readableBytes else {
            recorder.recordTLSClientInfo(version: clientVersion, recordVersion: recordVersion,
                                         cipherSuites: cipherSuites, sni: nil, alpn: nil)
            return
        }
        let compLen = Int(buffer.getInteger(at: pos, as: UInt8.self) ?? 0)
        pos += 1 + compLen

        // Extensions
        var sni: String?
        var alpn: [String]?

        guard pos + 2 <= buffer.readerIndex + buffer.readableBytes else {
            recorder.recordTLSClientInfo(version: clientVersion, recordVersion: recordVersion,
                                         cipherSuites: cipherSuites, sni: nil, alpn: nil)
            return
        }
        let extTotalLen = Int(buffer.getInteger(at: pos, as: UInt16.self) ?? 0)
        pos += 2
        let extEnd = pos + extTotalLen

        while pos + 4 <= extEnd && pos + 4 <= buffer.readerIndex + buffer.readableBytes {
            let extType = buffer.getInteger(at: pos, as: UInt16.self) ?? 0
            let extLen = Int(buffer.getInteger(at: pos + 2, as: UInt16.self) ?? 0)
            let extDataStart = pos + 4

            if extType == 0x0000 { // SNI
                sni = TLSSniffUtils.parseSNI(buffer, offset: extDataStart, length: extLen)
            } else if extType == 0x0010 { // ALPN
                alpn = TLSSniffUtils.parseALPN(buffer, offset: extDataStart, length: extLen)
            }
            pos = extDataStart + extLen
        }

        recorder.recordTLSClientInfo(version: clientVersion, recordVersion: recordVersion,
                                     cipherSuites: cipherSuites, sni: sni, alpn: alpn)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
    }
}

/// Sniffs the server→client direction (ServerHello + Certificate).
public final class TLSServerSniffHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    private let recorder: SessionRecorder
    private var gotServerHello = false
    private var gotCertificate = false

    public init(recorder: SessionRecorder) {
        self.recorder = recorder
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if !gotServerHello || !gotCertificate {
            let buffer = unwrapInboundIn(data)
            parseServerMessages(buffer)
            if gotServerHello && gotCertificate {
                context.pipeline.removeHandler(self, promise: nil)
            }
        }
        // Always forward
        context.fireChannelRead(data)
    }

    private func parseServerMessages(_ buffer: ByteBuffer) {
        var pos = buffer.readerIndex
        let end = buffer.readerIndex + buffer.readableBytes

        // May contain multiple TLS records
        while pos + 5 <= end {
            let contentType = buffer.getInteger(at: pos, as: UInt8.self) ?? 0
            let recordLen = Int(buffer.getInteger(at: pos + 3, as: UInt16.self) ?? 0)
            let recordDataStart = pos + 5

            guard contentType == 22, recordDataStart + recordLen <= end else { break } // Handshake only

            // Parse handshake message(s) within this record
            var hsPos = recordDataStart
            while hsPos + 4 <= recordDataStart + recordLen {
                let hsType = buffer.getInteger(at: hsPos, as: UInt8.self) ?? 0
                let hsLen = TLSSniffUtils.readUInt24(buffer, offset: hsPos + 1)

                if hsType == 2 && !gotServerHello { // ServerHello
                    parseServerHello(buffer, offset: hsPos + 4, length: hsLen)
                    gotServerHello = true
                } else if hsType == 11 && !gotCertificate { // Certificate
                    parseCertificateChain(buffer, offset: hsPos + 4, length: hsLen)
                    gotCertificate = true
                }

                hsPos += 4 + hsLen
            }

            pos = recordDataStart + recordLen
        }
    }

    private func parseServerHello(_ buffer: ByteBuffer, offset: Int, length: Int) {
        guard length >= 38 else { return }
        let version = TLSSniffUtils.readVersion(buffer, offset: offset)
        // Skip: version(2) + random(32) + sessionIdLen(1) + sessionId
        var pos = offset + 34
        guard pos < offset + length else { return }
        let sessionIdLen = Int(buffer.getInteger(at: pos, as: UInt8.self) ?? 0)
        pos += 1 + sessionIdLen

        // Selected cipher suite
        guard pos + 2 <= offset + length else { return }
        let selectedCipher = buffer.getInteger(at: pos, as: UInt16.self) ?? 0

        recorder.recordTLSServerInfo(version: version, selectedCipher: selectedCipher)
    }

    private func parseCertificateChain(_ buffer: ByteBuffer, offset: Int, length: Int) {
        guard length >= 3 else { return }
        let certsLen = TLSSniffUtils.readUInt24(buffer, offset: offset)
        var pos = offset + 3
        let end = min(offset + 3 + certsLen, offset + length)
        var subjects = [String]()

        while pos + 3 <= end {
            let certLen = TLSSniffUtils.readUInt24(buffer, offset: pos)
            pos += 3
            guard pos + certLen <= end else { break }

            // Extract CN from certificate DER (simplified — look for common name OID)
            if let cn = TLSSniffUtils.extractCNFromDER(buffer, offset: pos, length: certLen) {
                subjects.append(cn)
            }
            pos += certLen
        }

        recorder.recordTLSCertificateChain(subjects: subjects)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
    }
}

// MARK: - TLS Parsing Utilities

enum TLSSniffUtils {

    static func readVersion(_ buffer: ByteBuffer, offset: Int) -> String {
        let major = buffer.getInteger(at: offset, as: UInt8.self) ?? 0
        let minor = buffer.getInteger(at: offset + 1, as: UInt8.self) ?? 0
        switch (major, minor) {
        case (3, 0): return "SSL 3.0"
        case (3, 1): return "TLS 1.0"
        case (3, 2): return "TLS 1.1"
        case (3, 3): return "TLS 1.2"
        case (3, 4): return "TLS 1.3"
        default: return "\(major).\(minor)"
        }
    }

    static func readUInt24(_ buffer: ByteBuffer, offset: Int) -> Int {
        let b1 = Int(buffer.getInteger(at: offset, as: UInt8.self) ?? 0)
        let b2 = Int(buffer.getInteger(at: offset + 1, as: UInt8.self) ?? 0)
        let b3 = Int(buffer.getInteger(at: offset + 2, as: UInt8.self) ?? 0)
        return (b1 << 16) | (b2 << 8) | b3
    }

    static func parseSNI(_ buffer: ByteBuffer, offset: Int, length: Int) -> String? {
        // SNI extension: listLen(2) + type(1) + nameLen(2) + name
        guard length >= 5 else { return nil }
        let nameLen = Int(buffer.getInteger(at: offset + 3, as: UInt16.self) ?? 0)
        guard nameLen > 0, offset + 5 + nameLen <= offset + length else { return nil }
        return buffer.getString(at: offset + 5, length: nameLen)
    }

    static func parseALPN(_ buffer: ByteBuffer, offset: Int, length: Int) -> [String]? {
        // ALPN extension: listLen(2) + (protoLen(1) + proto)*
        guard length >= 2 else { return nil }
        let listLen = Int(buffer.getInteger(at: offset, as: UInt16.self) ?? 0)
        var pos = offset + 2
        let end = min(offset + 2 + listLen, offset + length)
        var protos = [String]()
        while pos + 1 <= end {
            let protoLen = Int(buffer.getInteger(at: pos, as: UInt8.self) ?? 0)
            pos += 1
            if protoLen > 0, pos + protoLen <= end,
               let proto = buffer.getString(at: pos, length: protoLen) {
                protos.append(proto)
            }
            pos += protoLen
        }
        return protos.isEmpty ? nil : protos
    }

    /// Best-effort CN extraction from DER certificate.
    /// Looks for OID 2.5.4.3 (commonName) followed by a UTF8String or PrintableString.
    static func extractCNFromDER(_ buffer: ByteBuffer, offset: Int, length: Int) -> String? {
        // OID 2.5.4.3 = 55 04 03
        let cnOID: [UInt8] = [0x55, 0x04, 0x03]
        let end = offset + length
        for i in offset..<(end - 5) {
            guard let b0 = buffer.getInteger(at: i, as: UInt8.self),
                  let b1 = buffer.getInteger(at: i + 1, as: UInt8.self),
                  let b2 = buffer.getInteger(at: i + 2, as: UInt8.self) else { continue }
            if b0 == cnOID[0] && b1 == cnOID[1] && b2 == cnOID[2] {
                // Next: tag(1) + length(1) + value
                let valueOffset = i + 3 + 2 // skip OID end + tag + length byte
                guard valueOffset < end else { return nil }
                let tag = buffer.getInteger(at: i + 3, as: UInt8.self) ?? 0
                // UTF8String(0x0C) or PrintableString(0x13)
                guard tag == 0x0C || tag == 0x13 else { continue }
                let strLen = Int(buffer.getInteger(at: i + 4, as: UInt8.self) ?? 0)
                guard strLen > 0, valueOffset + strLen <= end else { return nil }
                return buffer.getString(at: valueOffset, length: strLen)
            }
        }
        return nil
    }
}
