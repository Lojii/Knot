//
//  TestEchoServer.swift
//  TunnelServicesTests
//
//  A configurable NIO echo server for integration tests.
//  Supports HTTP/1.1, HTTP/2, WebSocket — with optional TLS.
//

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOHTTP2
import NIOWebSocket
import NIOSSL
import NIOTLS
@testable import TunnelServices

// MARK: - TestEchoServer

final class TestEchoServer {

    // MARK: Mode

    enum Mode {
        case http1
        case http1TLS(cert: NIOSSLCertificate, key: NIOSSLPrivateKey)
        case http2TLS(cert: NIOSSLCertificate, key: NIOSSLPrivateKey)
        case webSocket
        case webSocketTLS(cert: NIOSSLCertificate, key: NIOSSLPrivateKey)
    }

    // MARK: Options

    struct Options {
        var connectionHeader: String?
        var responseDelay: TimeAmount?
        var dropAfterHead: Bool = false

        init(
            connectionHeader: String? = nil,
            responseDelay: TimeAmount? = nil,
            dropAfterHead: Bool = false
        ) {
            self.connectionHeader = connectionHeader
            self.responseDelay = responseDelay
            self.dropAfterHead = dropAfterHead
        }
    }

    // MARK: Properties

    private let mode: Mode
    private let options: Options
    private var group: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    // MARK: Init

    init(mode: Mode, options: Options = Options()) {
        self.mode = mode
        self.options = options
    }

    // MARK: Lifecycle

    /// Bind to 127.0.0.1:0 and return the OS-assigned port.
    func start() throws -> Int {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let mode = self.mode
        let options = self.options

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                Self.configureChildChannel(channel, mode: mode, options: options)
            }

        let channel = try bootstrap.bind(host: "127.0.0.1", port: 0).wait()
        self.serverChannel = channel
        let port = channel.localAddress!.port!
        return port
    }

    /// Graceful shutdown.
    func stop() throws {
        try serverChannel?.close().wait()
        try group?.syncShutdownGracefully()
        serverChannel = nil
        group = nil
    }

    // MARK: - Certificate Helper

    static func generateServerCert() throws -> (NIOSSLCertificate, NIOSSLPrivateKey) {
        let (caCert, _, rsaKey) = try CertGenerator.generateCA()
        let serverCert = try CertGenerator.generateCert(
            host: "localhost",
            rsaKey: rsaKey,
            caKey: rsaKey,
            caCert: caCert
        )
        let niosslCert = try CertGenerator.toNIOSSL(serverCert)
        let niosslKey = try NIOSSLPrivateKey(bytes: Array(rsaKey.derRepresentation), format: .der)
        return (niosslCert, niosslKey)
    }

    // MARK: - Channel Configuration

    private static func configureChildChannel(
        _ channel: Channel,
        mode: Mode,
        options: Options
    ) -> EventLoopFuture<Void> {
        switch mode {
        case .http1:
            return configurePlainHTTP1(channel, options: options)

        case .http1TLS(let cert, let key):
            return configureTLS(
                channel,
                cert: cert,
                key: key,
                alpnProtocols: ["http/1.1"],
                options: options
            )

        case .http2TLS(let cert, let key):
            return configureTLS(
                channel,
                cert: cert,
                key: key,
                alpnProtocols: ["h2", "http/1.1"],
                options: options
            )

        case .webSocket:
            return configurePlainWebSocket(channel, options: options)

        case .webSocketTLS(let cert, let key):
            return configureTLS(
                channel,
                cert: cert,
                key: key,
                alpnProtocols: ["http/1.1"],
                options: options,
                isWebSocket: true
            )
        }
    }

    // MARK: Plain HTTP/1.1

    private static func configurePlainHTTP1(
        _ channel: Channel,
        options: Options
    ) -> EventLoopFuture<Void> {
        channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(EchoHTTPHandler(options: options))
        }
    }

    // MARK: Plain WebSocket

    private static func configurePlainWebSocket(
        _ channel: Channel,
        options: Options
    ) -> EventLoopFuture<Void> {
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, _ in
                channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, _ in
                channel.pipeline.addHandler(WebSocketEchoHandler())
            }
        )

        return channel.pipeline.configureHTTPServerPipeline(
            withServerUpgrade: (
                upgraders: [upgrader],
                completionHandler: { _ in }
            )
        ).flatMap {
            channel.pipeline.addHandler(EchoHTTPHandler(options: options))
        }
    }

    // MARK: TLS

    private static func configureTLS(
        _ channel: Channel,
        cert: NIOSSLCertificate,
        key: NIOSSLPrivateKey,
        alpnProtocols: [String],
        options: Options,
        isWebSocket: Bool = false
    ) -> EventLoopFuture<Void> {
        do {
            var tlsConfig = TLSConfiguration.makeServerConfiguration(
                certificateChain: [.certificate(cert)],
                privateKey: .privateKey(key)
            )
            tlsConfig.applicationProtocols = alpnProtocols
            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let sslHandler = NIOSSLServerHandler(context: sslContext)

            return channel.pipeline.addHandler(sslHandler).flatMap {
                channel.pipeline.addHandler(
                    ApplicationProtocolNegotiationHandler { result in
                        Self.alpnHandler(
                            result: result,
                            channel: channel,
                            options: options,
                            isWebSocket: isWebSocket
                        )
                    }
                )
            }
        } catch {
            return channel.eventLoop.makeFailedFuture(error)
        }
    }

    private static func alpnHandler(
        result: ALPNResult,
        channel: Channel,
        options: Options,
        isWebSocket: Bool
    ) -> EventLoopFuture<Void> {
        switch result {
        case .negotiated("h2"):
            return configureHTTP2(channel, options: options)
        case .negotiated("http/1.1"), .fallback:
            if isWebSocket {
                return configurePlainWebSocket(channel, options: options)
            } else {
                return configurePlainHTTP1(channel, options: options)
            }
        case .negotiated(let proto):
            print("TestEchoServer: unexpected ALPN protocol: \(proto)")
            return channel.close()
        }
    }

    // MARK: HTTP/2

    private static func configureHTTP2(
        _ channel: Channel,
        options: Options
    ) -> EventLoopFuture<Void> {
        channel.configureHTTP2Pipeline(mode: .server) { streamChannel in
            streamChannel.pipeline.addHandlers([
                HTTP2FramePayloadToHTTP1ServerCodec(),
                EchoHTTPHandler(options: options),
            ])
        }.map { _ in () }
    }
}

// MARK: - EchoHTTPHandler

private final class EchoHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let options: TestEchoServer.Options
    private var accumulatedBody = ByteBuffer()

    init(options: TestEchoServer.Options) {
        self.options = options
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head:
            accumulatedBody.clear()

        case .body(var buf):
            accumulatedBody.writeBuffer(&buf)

        case .end:
            sendResponse(context: context)
        }
    }

    private func sendResponse(context: ChannelHandlerContext) {
        let send = {
            var headers = HTTPHeaders()
            headers.add(name: "content-length", value: "\(self.accumulatedBody.readableBytes)")
            headers.add(name: "content-type", value: "application/octet-stream")
            if let conn = self.options.connectionHeader {
                headers.add(name: "connection", value: conn)
            }

            let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)

            if self.options.dropAfterHead {
                context.flush()
                context.close(promise: nil)
                return
            }

            context.write(self.wrapOutboundOut(.body(.byteBuffer(self.accumulatedBody))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }

        if let delay = options.responseDelay {
            context.eventLoop.scheduleTask(in: delay) {
                send()
            }
        } else {
            send()
        }
    }
}

// MARK: - WebSocketEchoHandler

private final class WebSocketEchoHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .text, .binary:
            // Echo it back — unmasked for server -> client
            let responseData = frame.unmaskedData
            let response = WebSocketFrame(
                fin: frame.fin,
                opcode: frame.opcode,
                data: responseData
            )
            context.writeAndFlush(wrapOutboundOut(response), promise: nil)

        case .connectionClose:
            // Echo the close frame back
            let closeData = frame.unmaskedData
            let closeFrame = WebSocketFrame(
                fin: true,
                opcode: .connectionClose,
                data: closeData
            )
            context.writeAndFlush(wrapOutboundOut(closeFrame)).whenComplete { _ in
                context.close(promise: nil)
            }

        case .ping:
            let pongData = frame.unmaskedData
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: pongData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)

        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - Smoke Test

#if DEBUG
import XCTest

final class TestEchoServerSmokeTest: XCTestCase {
    func testHTTP1ServerStartsAndStops() throws {
        let server = TestEchoServer(mode: .http1)
        let port = try server.start()
        XCTAssertTrue(port > 0 && port < 65536)
        try server.stop()
    }
}
#endif
