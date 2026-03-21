//
//  TestNIOClient.swift
//  TunnelServicesTests
//
//  A synchronous NIO-based HTTP client that sends requests THROUGH a proxy.
//  Supports HTTP/1.1, HTTPS (CONNECT), HTTP/2 (CONNECT), keep-alive, and WebSocket.
//  All methods use .wait() — acceptable in test code.
//

import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOHTTP2
import NIOHPACK
import NIOWebSocket
import NIOSSL
import NIOTLS
import NIOConcurrencyHelpers
@testable import TunnelServices

// MARK: - Response / Frame Types

struct TestHTTPResponse {
    let status: UInt
    let headers: [(String, String)]
    let body: Data
}

struct WebSocketTestFrame {
    enum FrameType {
        case text(String)
        case binary(Data)
        case close
    }
    let type: FrameType
}

// MARK: - WebSocket Test Session

final class WebSocketTestSession {
    private let channel: Channel
    private let frameQueue: WebSocketFrameQueue

    fileprivate init(channel: Channel, frameQueue: WebSocketFrameQueue) {
        self.channel = channel
        self.frameQueue = frameQueue
    }

    func send(_ text: String) throws {
        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        let maskKey = WebSocketMaskingKey.random()
        let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: maskKey, data: buffer)
        try channel.writeAndFlush(frame).wait()
    }

    func sendBinary(_ data: Data) throws {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let maskKey = WebSocketMaskingKey.random()
        let frame = WebSocketFrame(fin: true, opcode: .binary, maskKey: maskKey, data: buffer)
        try channel.writeAndFlush(frame).wait()
    }

    func receive(timeout: TimeAmount = .seconds(10)) throws -> WebSocketTestFrame {
        return try frameQueue.waitForFrame(timeout: timeout)
    }

    func close() throws {
        var buffer = channel.allocator.buffer(capacity: 2)
        // Normal closure status code: 1000
        buffer.writeInteger(UInt16(1000))
        let maskKey = WebSocketMaskingKey.random()
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: maskKey, data: buffer)
        try channel.writeAndFlush(frame).wait()
    }
}

// MARK: - TestNIOClient

final class TestNIOClient {
    let proxyHost: String
    let proxyPort: Int
    private let group: MultiThreadedEventLoopGroup

    init(proxyHost: String = "127.0.0.1", proxyPort: Int) {
        self.proxyHost = proxyHost
        self.proxyPort = proxyPort
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func shutdown() {
        try? group.syncShutdownGracefully()
    }

    // MARK: - 1. Plain HTTP/1.1 Through Proxy

    func httpRequest(
        method: HTTPMethod = .GET,
        host: String,
        port: Int,
        uri: String = "/",
        body: Data? = nil,
        headers: [(String, String)] = []
    ) throws -> TestHTTPResponse {
        let el = group.next()
        let responsePromise = el.makePromise(of: TestHTTPResponse.self)

        let bootstrap = ClientBootstrap(group: el)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(HTTPResponseCollector(promise: responsePromise))
                }
            }

        let channel = try bootstrap.connect(host: proxyHost, port: proxyPort).wait()

        // Build absolute-URI request for forward proxy
        let absoluteURI = "http://\(host):\(port)\(uri)"
        var httpHeaders = HTTPHeaders()
        httpHeaders.add(name: "Host", value: "\(host):\(port)")
        for (name, value) in headers {
            httpHeaders.add(name: name, value: value)
        }
        if let body = body {
            httpHeaders.add(name: "Content-Length", value: "\(body.count)")
        }

        let head = HTTPRequestHead(version: .http1_1, method: method, uri: absoluteURI, headers: httpHeaders)
        channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)

        if let body = body {
            var buf = channel.allocator.buffer(capacity: body.count)
            buf.writeBytes(body)
            channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
        }

        channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

        let response = try responsePromise.futureResult.wait()
        try? channel.close().wait()
        return response
    }

    // MARK: - 2. HTTPS via CONNECT Tunnel

    func httpsRequest(
        method: HTTPMethod = .GET,
        host: String,
        port: Int,
        uri: String = "/",
        body: Data? = nil,
        trustCA: NIOSSLCertificate? = nil,
        headers: [(String, String)] = []
    ) throws -> TestHTTPResponse {
        let el = group.next()

        // Step 1: Connect to proxy and issue CONNECT
        let connectPromise = el.makePromise(of: Void.self)
        let bootstrap = ClientBootstrap(group: el)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(CONNECTHandler(
                        targetHost: host,
                        targetPort: port,
                        promise: connectPromise
                    ))
                }
            }

        let channel = try bootstrap.connect(host: proxyHost, port: proxyPort).wait()

        // Wait for CONNECT 200
        try connectPromise.futureResult.wait()

        // Step 2: Remove HTTP handlers, add TLS + HTTP
        try removeHTTPHandlers(from: channel)

        let responsePromise = el.makePromise(of: TestHTTPResponse.self)

        // Add TLS — skip verification for MITM testing, as the proxy generates dynamic certs
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)

        // Add all handlers at once from the event loop to avoid races
        try channel.eventLoop.flatSubmit { () -> EventLoopFuture<Void> in
            channel.pipeline.addHandler(sslHandler, position: .first)
        }.wait()

        // Add HTTP handlers — the SSL handler will buffer data until handshake completes
        try channel.pipeline.addHTTPClientHandlers().wait()
        try channel.pipeline.addHandler(HTTPResponseCollector(promise: responsePromise)).wait()

        // Give the TLS handshake time to complete
        Thread.sleep(forTimeInterval: 0.5)

        // Step 3: Send the actual request (relative URI)
        var httpHeaders = HTTPHeaders()
        httpHeaders.add(name: "Host", value: "\(host):\(port)")
        for (name, value) in headers {
            httpHeaders.add(name: name, value: value)
        }
        if let body = body {
            httpHeaders.add(name: "Content-Length", value: "\(body.count)")
        }

        let head = HTTPRequestHead(version: .http1_1, method: method, uri: uri, headers: httpHeaders)
        channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)

        if let body = body {
            var buf = channel.allocator.buffer(capacity: body.count)
            buf.writeBytes(body)
            channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
        }

        channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

        // Schedule a timeout so we get a clear error instead of leaking the promise
        let timeoutTask = el.scheduleTask(in: .seconds(15)) {
            responsePromise.fail(TestNIOClientError.timeout)
        }

        let response: TestHTTPResponse
        do {
            response = try responsePromise.futureResult.wait()
            timeoutTask.cancel()
        } catch {
            timeoutTask.cancel()
            try? channel.close().wait()
            throw error
        }
        try? channel.close().wait()
        return response
    }

    // MARK: - 3. HTTP/2 via CONNECT Tunnel

    func h2Request(
        host: String,
        port: Int,
        uri: String = "/",
        body: Data? = nil,
        trustCA: NIOSSLCertificate? = nil,
        headers: [(String, String)] = []
    ) throws -> TestHTTPResponse {
        let el = group.next()

        // Step 1: CONNECT tunnel
        let connectPromise = el.makePromise(of: Void.self)
        let bootstrap = ClientBootstrap(group: el)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(CONNECTHandler(
                        targetHost: host,
                        targetPort: port,
                        promise: connectPromise
                    ))
                }
            }

        let channel = try bootstrap.connect(host: proxyHost, port: proxyPort).wait()
        try connectPromise.futureResult.wait()

        // Step 2: Remove HTTP handlers, add TLS with h2 ALPN
        try removeHTTPHandlers(from: channel)

        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        if let ca = trustCA {
            tlsConfig.trustRoots = .certificates([ca])
        }
        tlsConfig.certificateVerification = trustCA != nil ? .fullVerification : .none
        tlsConfig.applicationProtocols = ["h2"]
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)

        try channel.pipeline.addHandler(sslHandler, position: .first).wait()

        // Wait for TLS
        let h2TlsEventsHandler = TLSEventsHandler(eventLoop: el)
        try channel.pipeline.addHandler(h2TlsEventsHandler).wait()
        try h2TlsEventsHandler.waitForHandshake()

        // Step 3: Add HTTP/2 handler
        let responsePromise = el.makePromise(of: TestHTTPResponse.self)

        let h2Handler = NIOHTTP2Handler(mode: .client)
        try channel.pipeline.addHandler(h2Handler).wait()

        let multiplexer = HTTP2StreamMultiplexer(mode: .client, channel: channel) { stream in
            stream.eventLoop.makeSucceededVoidFuture()
        }
        try channel.pipeline.addHandler(multiplexer).wait()

        // Step 4: Create a stream and send request
        let streamPromise = el.makePromise(of: Channel.self)
        multiplexer.createStreamChannel(promise: streamPromise) { streamChannel in
            streamChannel.pipeline.addHandlers([
                HTTP2FramePayloadToHTTP1ClientCodec(httpProtocol: .https),
                HTTPResponseCollector(promise: responsePromise),
            ])
        }

        let streamChannel = try streamPromise.futureResult.wait()

        // Build request
        var httpHeaders = HTTPHeaders()
        httpHeaders.add(name: "Host", value: "\(host):\(port)")
        for (name, value) in headers {
            httpHeaders.add(name: name, value: value)
        }
        if let body = body {
            httpHeaders.add(name: "Content-Length", value: "\(body.count)")
        }

        let method: HTTPMethod = body != nil ? .POST : .GET
        let head = HTTPRequestHead(version: .http1_1, method: method, uri: uri, headers: httpHeaders)
        streamChannel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)

        if let body = body {
            var buf = streamChannel.allocator.buffer(capacity: body.count)
            buf.writeBytes(body)
            streamChannel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
        }

        streamChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

        let response = try responsePromise.futureResult.wait()
        try? channel.close().wait()
        return response
    }

    // MARK: - 4. Keep-Alive Multiple HTTP/1.1 on Same Connection

    func httpKeepAliveRequests(
        host: String,
        port: Int,
        requests: [(method: HTTPMethod, uri: String, body: Data?)]
    ) throws -> [TestHTTPResponse] {
        let el = group.next()
        var responses: [TestHTTPResponse] = []

        // Single connection to proxy
        let firstPromise = el.makePromise(of: TestHTTPResponse.self)
        let collector = HTTPResponseCollector(promise: firstPromise)

        let bootstrap = ClientBootstrap(group: el)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(collector)
                }
            }

        let channel = try bootstrap.connect(host: proxyHost, port: proxyPort).wait()

        for (index, req) in requests.enumerated() {
            let promise: EventLoopPromise<TestHTTPResponse>
            if index == 0 {
                promise = firstPromise
            } else {
                promise = el.makePromise(of: TestHTTPResponse.self)
                collector.reset(promise: promise)
            }

            let absoluteURI = "http://\(host):\(port)\(req.uri)"
            var httpHeaders = HTTPHeaders()
            httpHeaders.add(name: "Host", value: "\(host):\(port)")
            httpHeaders.add(name: "Connection", value: "keep-alive")
            if let body = req.body {
                httpHeaders.add(name: "Content-Length", value: "\(body.count)")
            }

            let head = HTTPRequestHead(version: .http1_1, method: req.method, uri: absoluteURI, headers: httpHeaders)
            channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)

            if let body = req.body {
                var buf = channel.allocator.buffer(capacity: body.count)
                buf.writeBytes(body)
                channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buf))), promise: nil)
            }

            channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

            let response = try promise.futureResult.wait()
            responses.append(response)
        }

        try? channel.close().wait()
        return responses
    }

    // MARK: - 5. WebSocket Through Proxy

    func webSocketSession(
        host: String,
        port: Int,
        path: String = "/",
        tls: Bool = false,
        trustCA: NIOSSLCertificate? = nil,
        handler: (WebSocketTestSession) throws -> Void
    ) throws {
        let el = group.next()

        let channel: Channel

        if tls {
            // WSS: CONNECT tunnel + TLS first
            let connectPromise = el.makePromise(of: Void.self)
            let bootstrap = ClientBootstrap(group: el)
                .connectTimeout(.seconds(10))
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers().flatMap {
                        channel.pipeline.addHandler(CONNECTHandler(
                            targetHost: host,
                            targetPort: port,
                            promise: connectPromise
                        ))
                    }
                }

            channel = try bootstrap.connect(host: proxyHost, port: proxyPort).wait()
            try connectPromise.futureResult.wait()

            // Remove HTTP handlers, add TLS
            try removeHTTPHandlers(from: channel)

            // Skip TLS verification for MITM testing — the proxy generates
            // dynamic certs that won't pass fullVerification.
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.certificateVerification = .none
            let sslContext = try NIOSSLContext(configuration: tlsConfig)
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
            try channel.pipeline.addHandler(sslHandler, position: .first).wait()
            let wsTlsEventsHandler = TLSEventsHandler(eventLoop: el)
            try channel.pipeline.addHandler(wsTlsEventsHandler).wait()
            try wsTlsEventsHandler.waitForHandshake()

            // Add HTTP handlers for upgrade request
            try channel.pipeline.addHTTPClientHandlers().wait()
        } else {
            // WS: direct to proxy
            let bootstrap = ClientBootstrap(group: el)
                .connectTimeout(.seconds(10))
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers()
                }

            channel = try bootstrap.connect(host: proxyHost, port: proxyPort).wait()
        }

        // Send WebSocket upgrade request.
        // The WebSocketUpgradeHandler handles 101 and atomically swaps the pipeline
        // to WS mode (removes HTTP handlers, adds WS decoder/encoder/inbound handler)
        // on the event loop BEFORE returning from channelRead. This prevents a race
        // where the proxy sends WS frames before we've finished pipeline reconfiguration.
        let frameQueue = WebSocketFrameQueue(eventLoop: el)
        let upgradePromise = el.makePromise(of: Void.self)
        try channel.pipeline.addHandler(
            WebSocketUpgradeHandler(promise: upgradePromise, frameQueue: frameQueue)
        ).wait()

        let keyBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let wsKey = Data(keyBytes).base64EncodedString()

        let upgradeURI: String
        if tls {
            upgradeURI = path
        } else {
            upgradeURI = "http://\(host):\(port)\(path)"
        }

        var httpHeaders = HTTPHeaders()
        httpHeaders.add(name: "Host", value: "\(host):\(port)")
        httpHeaders.add(name: "Connection", value: "Upgrade")
        httpHeaders.add(name: "Upgrade", value: "websocket")
        httpHeaders.add(name: "Sec-WebSocket-Key", value: wsKey)
        httpHeaders.add(name: "Sec-WebSocket-Version", value: "13")

        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: upgradeURI, headers: httpHeaders)
        channel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
        channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)

        // Wait for 101 + pipeline swap (done atomically by WebSocketUpgradeHandler)
        try upgradePromise.futureResult.wait()

        let session = WebSocketTestSession(channel: channel, frameQueue: frameQueue)

        // Run the user's handler
        try handler(session)

        try? channel.close().wait()
    }

    // MARK: - 6. Raw CONNECT Tunnel

    func rawConnect(host: String, port: Int) throws -> Channel {
        let el = group.next()
        let connectPromise = el.makePromise(of: Void.self)

        let bootstrap = ClientBootstrap(group: el)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(CONNECTHandler(
                        targetHost: host,
                        targetPort: port,
                        promise: connectPromise
                    ))
                }
            }

        let channel = try bootstrap.connect(host: proxyHost, port: proxyPort).wait()
        try connectPromise.futureResult.wait()

        // Remove HTTP handlers — caller gets a raw tunnel
        try removeHTTPHandlers(from: channel)

        return channel
    }

    // MARK: - Pipeline Helpers

    /// Remove HTTP codec handlers from the pipeline after a CONNECT 200 response.
    private func removeHTTPHandlers(from channel: Channel) throws {
        // Use the event loop to safely remove handlers
        try channel.eventLoop.submit {
            let pipeline = channel.pipeline
            // Try to remove standard HTTP client handlers by type
            if let handler = try? pipeline.syncOperations.handler(type: HTTPRequestEncoder.self) {
                _ = pipeline.syncOperations.removeHandler(handler)
            }
            if let handler = try? pipeline.syncOperations.handler(type: ByteToMessageHandler<HTTPResponseDecoder>.self) {
                _ = pipeline.syncOperations.removeHandler(handler)
            }
            // Also try removing NIOHTTPClientUpgradeHandler if present
            if let handler = try? pipeline.syncOperations.handler(type: NIOHTTPClientUpgradeHandler.self) {
                _ = pipeline.syncOperations.removeHandler(handler)
            }
            // Remove NIOHTTPRequestHeadersValidator added by addHTTPClientHandlers()
            // to prevent duplicate validators when HTTP handlers are re-added after CONNECT.
            if let handler = try? pipeline.syncOperations.handler(type: NIOHTTPRequestHeadersValidator.self) {
                _ = pipeline.syncOperations.removeHandler(handler)
            }
        }.wait()
    }
}

// MARK: - HTTPResponseCollector

private final class HTTPResponseCollector: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private var head: HTTPResponseHead?
    private var body = Data()
    private var promise: EventLoopPromise<TestHTTPResponse>

    init(promise: EventLoopPromise<TestHTTPResponse>) {
        self.promise = promise
    }

    /// Reset the collector for re-use on keep-alive connections.
    func reset(promise: EventLoopPromise<TestHTTPResponse>) {
        self.head = nil
        self.body = Data()
        self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h):
            head = h
        case .body(var buf):
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                body.append(contentsOf: bytes)
            }
        case .end:
            let response = TestHTTPResponse(
                status: UInt(head?.status.code ?? 0),
                headers: head?.headers.map { ($0.name, $0.value) } ?? [],
                body: body
            )
            promise.succeed(response)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
    }
}

// MARK: - CONNECTHandler

private final class CONNECTHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let targetHost: String
    private let targetPort: Int
    private let promise: EventLoopPromise<Void>
    private var sent = false

    init(targetHost: String, targetPort: Int, promise: EventLoopPromise<Void>) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.promise = promise
    }

    func channelActive(context: ChannelHandlerContext) {
        guard !sent else { return }
        sent = true

        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(targetHost):\(targetPort)")

        let head = HTTPRequestHead(
            version: .http1_1,
            method: .CONNECT,
            uri: "\(targetHost):\(targetPort)",
            headers: headers
        )

        context.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
        context.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // If channel is already active when handler is added, send CONNECT now
        if context.channel.isActive && !sent {
            channelActive(context: context)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            if head.status == .ok {
                // 200 Connection Established — remove self, signal success
                context.pipeline.removeHandler(self, promise: nil)
                promise.succeed(())
            } else {
                promise.fail(TestNIOClientError.connectFailed(status: head.status.code))
            }
        case .body:
            break
        case .end:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
    }
}

// MARK: - TLSEventsHandler

/// Waits for the TLS handshake to complete before allowing further pipeline setup.
private final class TLSEventsHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = NIOAny

    let handshakePromise: EventLoopPromise<Void>

    init(eventLoop: EventLoop) {
        self.handshakePromise = eventLoop.makePromise(of: Void.self)
    }

    /// Block until the TLS handshake completes or fails.
    func waitForHandshake() throws {
        try handshakePromise.futureResult.wait()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let tlsEvent = event as? TLSUserEvent {
            switch tlsEvent {
            case .handshakeCompleted:
                handshakePromise.succeed(())
            case .shutdownCompleted:
                break
            }
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        handshakePromise.fail(error)
        context.fireErrorCaught(error)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // Don't block — we just install and wait
    }
}

// MARK: - WebSocketUpgradeHandler

/// Handles the HTTP 101 response during WebSocket upgrade.
/// Waits for HTTP 101 Switching Protocols, then removes HTTP handlers and
/// installs WebSocket handlers atomically on the event loop, before the promise fires.
/// This prevents a race where the proxy sends WS frames before the client has swapped pipelines.
private final class WebSocketUpgradeHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let promise: EventLoopPromise<Void>
    private let frameQueue: WebSocketFrameQueue
    private var gotUpgrade = false

    init(promise: EventLoopPromise<Void>, frameQueue: WebSocketFrameQueue) {
        self.promise = promise
        self.frameQueue = frameQueue
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            if head.status == .switchingProtocols {
                gotUpgrade = true
            } else {
                promise.fail(TestNIOClientError.webSocketUpgradeFailed(status: head.status.code))
            }
        case .body:
            break
        case .end:
            // Wait for .end before swapping pipeline — ensures all HTTP response
            // parts are consumed before we remove the HTTP decoder.
            guard gotUpgrade else { return }

            let pipeline = context.pipeline

            // 1. Remove this handler
            pipeline.removeHandler(self, promise: nil)

            // 2. Remove HTTP handlers by type
            func removeByType<T: RemovableChannelHandler>(_ type: T.Type) {
                if let h = try? pipeline.syncOperations.handler(type: type) {
                    try? pipeline.syncOperations.removeHandler(h)
                }
            }
            removeByType(HTTPRequestEncoder.self)
            removeByType(ByteToMessageHandler<HTTPResponseDecoder>.self)
            removeByType(NIOHTTPRequestHeadersValidator.self)

            // 3. Add WS handlers
            _ = try? pipeline.syncOperations.addHandler(
                ByteToMessageHandler(WebSocketFrameDecoder(maxFrameSize: 1 << 20)))
            _ = try? pipeline.syncOperations.addHandler(WebSocketFrameEncoder())
            _ = try? pipeline.syncOperations.addHandler(
                WebSocketClientInboundHandler(frameQueue: frameQueue))

            promise.succeed(())
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
    }
}

// MARK: - WebSocketFrameQueue

/// Thread-safe queue for receiving WebSocket frames in tests.
final class WebSocketFrameQueue {
    private let eventLoop: EventLoop
    private var frames: [WebSocketTestFrame] = []
    private var waiters: [EventLoopPromise<WebSocketTestFrame>] = []
    private let lock = NIOLock()

    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }

    func enqueue(_ frame: WebSocketTestFrame) {
        lock.withLock {
            if let waiter = waiters.first {
                waiters.removeFirst()
                waiter.succeed(frame)
            } else {
                frames.append(frame)
            }
        }
    }

    func waitForFrame(timeout: TimeAmount = .seconds(10)) throws -> WebSocketTestFrame {
        let result: WebSocketTestFrame? = lock.withLock { () -> WebSocketTestFrame? in
            if !frames.isEmpty {
                return frames.removeFirst()
            }
            return nil
        }

        if let frame = result {
            return frame
        }

        // Need to wait
        let promise = eventLoop.makePromise(of: WebSocketTestFrame.self)
        lock.withLock {
            waiters.append(promise)
        }

        // Schedule timeout
        let timeoutTask = eventLoop.scheduleTask(in: timeout) {
            promise.fail(TestNIOClientError.timeout)
        }

        do {
            let frame = try promise.futureResult.wait()
            timeoutTask.cancel()
            return frame
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }
}

// MARK: - WebSocketClientInboundHandler

private final class WebSocketClientInboundHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame

    private let frameQueue: WebSocketFrameQueue

    init(frameQueue: WebSocketFrameQueue) {
        self.frameQueue = frameQueue
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        let unmasked = frame.unmaskedData

        switch frame.opcode {
        case .text:
            if let str = unmasked.getString(at: unmasked.readerIndex, length: unmasked.readableBytes) {
                frameQueue.enqueue(WebSocketTestFrame(type: .text(str)))
            }
        case .binary:
            if let bytes = unmasked.getBytes(at: unmasked.readerIndex, length: unmasked.readableBytes) {
                frameQueue.enqueue(WebSocketTestFrame(type: .binary(Data(bytes))))
            }
        case .connectionClose:
            frameQueue.enqueue(WebSocketTestFrame(type: .close))
        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

// MARK: - Errors

enum TestNIOClientError: Error, CustomStringConvertible {
    case connectFailed(status: UInt)
    case webSocketUpgradeFailed(status: UInt)
    case timeout
    case unexpectedResponse

    var description: String {
        switch self {
        case .connectFailed(let status):
            return "CONNECT tunnel failed with status \(status)"
        case .webSocketUpgradeFailed(let status):
            return "WebSocket upgrade failed with status \(status)"
        case .timeout:
            return "Operation timed out"
        case .unexpectedResponse:
            return "Received unexpected response"
        }
    }
}
