//
//  SOCKSProxyHandler.swift
//  TunnelServices
//
//  SOCKS5 proxy server handler.
//  Accepts SOCKS5 connections and routes them through the existing proxy pipeline.
//
//  Netty reference: codec-socks/Socks5CommandRequest.java,
//                   handler-proxy/Socks5ProxyHandler.java
//

import Foundation
import NIO

// MARK: - SOCKS5 Constants

private enum SOCKS5 {
    static let version: UInt8 = 0x05
    enum AuthMethod: UInt8 { case noAuth = 0x00, usernamePassword = 0x02, noAcceptable = 0xFF }
    enum Command: UInt8 { case connect = 0x01, bind = 0x02, udpAssociate = 0x03 }
    enum AddressType: UInt8 { case ipv4 = 0x01, domain = 0x03, ipv6 = 0x04 }
    enum Reply: UInt8 {
        case succeeded = 0x00, generalFailure = 0x01, connectionNotAllowed = 0x02
        case networkUnreachable = 0x03, hostUnreachable = 0x04, connectionRefused = 0x05
        case ttlExpired = 0x06, commandNotSupported = 0x07, addressTypeNotSupported = 0x08
    }
}

// MARK: - SOCKS5 Server Handler

/// Handles the SOCKS5 handshake and then delegates to ProtocolDispatcher or TunnelHandler.
public final class SOCKS5ServerHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let task: CaptureTask
    private let requireAuth: Bool
    private let username: String?
    private let password: String?

    private enum State { case greeting, auth, request, relaying }
    private var state: State = .greeting

    public init(task: CaptureTask, username: String? = nil, password: String? = nil) {
        self.task = task
        self.requireAuth = username != nil
        self.username = username
        self.password = password
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)

        switch state {
        case .greeting:
            handleGreeting(context: context, buffer: &buffer)
        case .auth:
            handleAuth(context: context, buffer: &buffer)
        case .request:
            handleRequest(context: context, buffer: &buffer)
        case .relaying:
            context.fireChannelRead(data)
        }
    }

    // MARK: - Phase 1: Greeting

    private func handleGreeting(context: ChannelHandlerContext, buffer: inout ByteBuffer) {
        guard let version = buffer.readInteger(as: UInt8.self), version == SOCKS5.version,
              let methodCount = buffer.readInteger(as: UInt8.self) else {
            closeWithError(context: context); return
        }

        var methods = [UInt8]()
        for _ in 0..<methodCount {
            if let m = buffer.readInteger(as: UInt8.self) { methods.append(m) }
        }

        let selectedMethod: UInt8
        if requireAuth && methods.contains(SOCKS5.AuthMethod.usernamePassword.rawValue) {
            selectedMethod = SOCKS5.AuthMethod.usernamePassword.rawValue
            state = .auth
        } else if methods.contains(SOCKS5.AuthMethod.noAuth.rawValue) && !requireAuth {
            selectedMethod = SOCKS5.AuthMethod.noAuth.rawValue
            state = .request
        } else {
            selectedMethod = SOCKS5.AuthMethod.noAcceptable.rawValue
        }

        var response = context.channel.allocator.buffer(capacity: 2)
        response.writeInteger(SOCKS5.version)
        response.writeInteger(selectedMethod)
        context.writeAndFlush(wrapOutboundOut(response), promise: nil)

        if selectedMethod == SOCKS5.AuthMethod.noAcceptable.rawValue {
            context.close(promise: nil)
        }
    }

    // MARK: - Phase 2: Authentication

    private func handleAuth(context: ChannelHandlerContext, buffer: inout ByteBuffer) {
        guard let _ = buffer.readInteger(as: UInt8.self),  // version (0x01)
              let uLen = buffer.readInteger(as: UInt8.self),
              let user = buffer.readString(length: Int(uLen)),
              let pLen = buffer.readInteger(as: UInt8.self),
              let pass = buffer.readString(length: Int(pLen)) else {
            closeWithError(context: context); return
        }

        let success = (user == username && pass == password)
        var response = context.channel.allocator.buffer(capacity: 2)
        response.writeInteger(UInt8(0x01))
        response.writeInteger(UInt8(success ? 0x00 : 0x01))
        context.writeAndFlush(wrapOutboundOut(response), promise: nil)

        if success {
            state = .request
        } else {
            context.close(promise: nil)
        }
    }

    // MARK: - Phase 3: Connection Request

    private func handleRequest(context: ChannelHandlerContext, buffer: inout ByteBuffer) {
        guard let version = buffer.readInteger(as: UInt8.self), version == SOCKS5.version,
              let command = buffer.readInteger(as: UInt8.self),
              let _ = buffer.readInteger(as: UInt8.self),  // reserved
              let addrType = buffer.readInteger(as: UInt8.self) else {
            sendReply(context: context, reply: .generalFailure); return
        }

        guard command == SOCKS5.Command.connect.rawValue else {
            sendReply(context: context, reply: .commandNotSupported); return
        }

        // Parse destination address
        let host: String
        switch addrType {
        case SOCKS5.AddressType.ipv4.rawValue:
            guard let a = buffer.readInteger(as: UInt8.self),
                  let b = buffer.readInteger(as: UInt8.self),
                  let c = buffer.readInteger(as: UInt8.self),
                  let d = buffer.readInteger(as: UInt8.self) else {
                sendReply(context: context, reply: .generalFailure); return
            }
            host = "\(a).\(b).\(c).\(d)"

        case SOCKS5.AddressType.domain.rawValue:
            guard let domainLen = buffer.readInteger(as: UInt8.self),
                  let domain = buffer.readString(length: Int(domainLen)) else {
                sendReply(context: context, reply: .generalFailure); return
            }
            host = domain

        case SOCKS5.AddressType.ipv6.rawValue:
            guard buffer.readableBytes >= 16 else {
                sendReply(context: context, reply: .addressTypeNotSupported); return
            }
            var parts = [String]()
            for _ in 0..<8 {
                if let word = buffer.readInteger(as: UInt16.self) {
                    parts.append(String(format: "%x", word))
                }
            }
            host = parts.joined(separator: ":")

        default:
            sendReply(context: context, reply: .addressTypeNotSupported); return
        }

        guard let port = buffer.readInteger(as: UInt16.self) else {
            sendReply(context: context, reply: .generalFailure); return
        }

        AxLogger.log("SOCKS5 CONNECT \(host):\(port)", level: .Info)

        // Send success reply
        sendReply(context: context, reply: .succeeded)
        state = .relaying

        // Remove SOCKS handler and set up tunnel with recording
        let recorder = SessionRecorder(task: task)
        recorder.session.host = host

        _ = context.pipeline.removeHandler(self)

        let isLikelyTLS = (port == 443 || port == 8443)

        if isLikelyTLS {
            // HTTPS via SOCKS5 — sniff TLS handshake, record as HTTPS tunnel
            recorder.session.schemes = "SOCKS5/HTTPS"
            recorder.ensureHttpRecorder(
                host: host, port: Int(port),
                protocolOverride: "HTTPS",
                method: "SOCKS5 CONNECT", uri: "\(host):\(port)",
                extraMetadata: ["encrypted": true, "decrypted": false, "proxy": "SOCKS5"]
            )
            _ = context.pipeline.addHandler(
                TLSClientSniffHandler(recorder: recorder), name: "tls.sniff.client", position: .first
            )
        } else {
            // Non-TLS via SOCKS5 — record as TCP tunnel
            recorder.session.schemes = "SOCKS5"
            recorder.ensureHttpRecorder(
                host: host, port: Int(port),
                protocolOverride: "TCP",
                method: "SOCKS5 CONNECT", uri: "\(host):\(port)",
                extraMetadata: ["proxy": "SOCKS5"]
            )
        }

        let tunnel = TunnelHandler(recorder: recorder, task: task, targetHost: host, targetPort: Int(port))
        _ = context.pipeline.addHandler(tunnel, name: "socks.tunnel")
    }

    // MARK: - Helpers

    private func sendReply(context: ChannelHandlerContext, reply: SOCKS5.Reply) {
        var response = context.channel.allocator.buffer(capacity: 10)
        response.writeInteger(SOCKS5.version)
        response.writeInteger(reply.rawValue)
        response.writeInteger(UInt8(0x00))  // reserved
        response.writeInteger(SOCKS5.AddressType.ipv4.rawValue)
        response.writeInteger(UInt32(0))     // bind addr 0.0.0.0
        response.writeInteger(UInt16(0))     // bind port 0
        context.writeAndFlush(wrapOutboundOut(response), promise: nil)

        if reply != .succeeded { context.close(promise: nil) }
    }

    private func closeWithError(context: ChannelHandlerContext) {
        context.close(promise: nil)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
