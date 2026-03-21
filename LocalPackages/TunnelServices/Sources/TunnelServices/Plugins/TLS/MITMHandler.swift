//
//  MITMHandler.swift
//  TunnelServices
//
//  Performs TLS interception (Man-in-the-Middle).
//  1. Receives ClientHello from client
//  2. Generates a dynamic certificate for the target host
//  3. Sets up NIOSSLServerHandler to complete TLS handshake with client
//  4. After handshake, adds HTTP capture pipeline to inspect decrypted traffic
//

import Foundation
import NIO
import NIOHTTP1
import NIOSSL
import NIOTLS
import NIOHTTPCompression

public final class MITMHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    private let task: CaptureTask
    private let recorder: SessionRecorder
    private let host: String
    private let port: Int
    private var handshakeTimeout: Scheduled<Void>?

    public init(task: CaptureTask, recorder: SessionRecorder, host: String, port: Int) {
        self.task = task
        self.recorder = recorder
        self.host = host
        self.port = port
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        handshakeTimeout?.cancel()
        let buffer = unwrapInboundIn(data)

        AxLogger.log("[MITM] channelRead for \(host):\(port), bytes=\(buffer.readableBytes)", level: .Warning)

        // Validate TLS ClientHello
        guard isTLSClientHello(buffer) else {
            AxLogger.log("Expected TLS ClientHello but got non-TLS data for \(host)", level: .Error)
            recorder.recordError("error:not a TLS ClientHello")
            context.channel.close(mode: .all, promise: nil)
            return
        }

        // Generate or retrieve cached certificate
        guard let certMgr = task.certManager,
              let x509CACert = certMgr.x509CACert,
              let rsaSigningKey = certMgr.rsaSigningKey,
              let rsaKey = certMgr.rsakey else {
            AxLogger.log("Certificates not loaded for \(host), falling back to tunnel", level: .Warning)
            // Fallback to tunnel passthrough instead of closing
            fallbackToTunnel(context: context, buffer: buffer)
            return
        }

        var niosslCert = certMgr.certPool[host]
        if niosslCert == nil {
            do {
                let x509Cert = try CertGenerator.generateCert(
                    host: host, rsaKey: rsaSigningKey, caKey: rsaSigningKey, caCert: x509CACert
                )
                niosslCert = try CertGenerator.toNIOSSL(x509Cert)
                if let cert = niosslCert {
                    certMgr.certPool.set(cert, forKey: host)
                }
            } catch {
                AxLogger.log("Failed to generate cert for \(host): \(error)", level: .Error)
                recorder.recordError("error:cert generation failed for \(host)")
                context.channel.close(mode: .all, promise: nil)
                return
            }
        }

        guard let cert = niosslCert else {
            recorder.recordError("error:no cert available for \(host)")
            context.channel.close(mode: .all, promise: nil)
            return
        }

        // Create TLS server context — advertise both h2 and http/1.1
        AxLogger.log("[MITM] Setting up TLS context for \(host), cert ready", level: .Warning)
        let tlsConfig = TLSConfiguration.forServer(
            certificateChain: [.certificate(cert)],
            privateKey: .privateKey(rsaKey),
            applicationProtocols: ["h2", "http/1.1"]
        )

        guard let sslContext = try? NIOSSLContext(configuration: tlsConfig),
              let sslHandler = try? NIOSSLServerHandler(context: sslContext) else {
            AxLogger.log("Failed to create SSL context for \(host)", level: .Error)
            recorder.recordError("error:SSL context creation failed for \(host)")
            context.channel.close(mode: .all, promise: nil)
            return
        }

        AxLogger.log("[MITM] TLS handshake starting with client for \(host)", level: .Warning)

        // Set up handshake timeout
        let handshakeTimeoutTask = context.channel.eventLoop.scheduleTask(
            in: .seconds(ProxyConfig.SSL.handshakeTimeout)
        ) { [weak self] in
            AxLogger.log("[MITM] Handshake TIMEOUT for \(self?.host ?? "") — client may not trust our CA certificate", level: .Warning)
            self?.recorder.recordError("error:MITM handshake timeout for \(self?.host ?? "") — CA certificate may not be installed on device")
            context.channel.close(mode: .all, promise: nil)
        }

        // ALPN handler: after TLS handshake, add HTTP/1.1 or HTTP/2 pipeline
        let alpnHandler = ApplicationProtocolNegotiationHandler { [weak self] result -> EventLoopFuture<Void> in
            handshakeTimeoutTask.cancel()
            guard let self = self else { return context.eventLoop.makeSucceededVoidFuture() }
            AxLogger.log("[MITM] TLS handshake SUCCEEDED for \(self.host), ALPN result: \(result)", level: .Warning)
            self.recorder.recordHandshakeComplete()

            // Check ALPN result to decide HTTP version
            switch result {
            case .negotiated("h2"):
                // HTTP/2 (gRPC, standard H2 traffic)
                self.recorder.session.schemes = "H2"
                AxLogger.log("[MITM] ALPN negotiated h2 for \(self.host)", level: .Warning)
                return HTTP2CaptureBuilder.addPipeline(
                    context: context, recorder: self.recorder,
                    targetHost: self.host, targetPort: self.port
                )
            default:
                // HTTP/1.1 (default)
                return self.addHTTPCapturePipeline(context: context)
            }
        }

        // Add handlers: SSL → ALPN → (HTTP pipeline added after handshake)
        _ = context.pipeline.addHandler(sslHandler, name: "mitm.ssl", position: .last)
        _ = context.pipeline.addHandler(alpnHandler, name: "mitm.alpn")

        // Forward the ClientHello data to the SSL handler
        context.fireChannelRead(wrapInboundOut(buffer))

        // Remove ourselves
        _ = context.pipeline.removeHandler(name: "mitm")
    }

    private func addHTTPCapturePipeline(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
        let captureHandler = HTTPCaptureHandler(recorder: recorder, isSSL: true, targetPort: port)
        return context.pipeline.addHandler(
            ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)),
            name: "mitm.http.requestDecoder"
        ).flatMap {
            context.pipeline.addHandler(HTTPResponseEncoder(), name: "mitm.http.responseEncoder")
        }.flatMap {
            context.pipeline.addHandler(HTTPServerPipelineHandler(), name: "mitm.http.pipelining")
        }.flatMap {
            context.pipeline.addHandler(captureHandler, name: "mitm.http.capture")
        }
    }

    /// Fallback: when MITM can't proceed (no certs), switch to tunnel passthrough.
    /// Records the connection as HTTPS(Tunnel) so it still appears in the UI.
    private func fallbackToTunnel(context: ChannelHandlerContext, buffer: ByteBuffer) {
        recorder.session.schemes = "HTTPS(Tunnel)"
        recorder.ensureHttpRecorder(
            host: host, port: port,
            protocolOverride: "HTTPS",
            method: "CONNECT", uri: "\(host):\(port)",
            extraMetadata: ["encrypted": true, "decrypted": false]
        )
        // Sniff TLS handshake before tunneling
        _ = context.pipeline.addHandler(
            TLSClientSniffHandler(recorder: recorder), name: "tls.sniff.client", position: .first
        )
        let tunnel = TunnelHandler(
            recorder: recorder,
            task: task,
            targetHost: host,
            targetPort: port
        )
        _ = context.pipeline.addHandler(tunnel, name: "tunnel")
        // Forward the buffered ClientHello to start the tunnel
        context.fireChannelRead(wrapInboundOut(buffer))
        _ = context.pipeline.removeHandler(name: "mitm")
    }

    private func isTLSClientHello(_ buffer: ByteBuffer) -> Bool {
        guard buffer.readableBytes >= 3 else { return false }
        let b1 = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) ?? 0
        let b2 = buffer.getInteger(at: buffer.readerIndex + 1, as: UInt8.self) ?? 0
        let b3 = buffer.getInteger(at: buffer.readerIndex + 2, as: UInt8.self) ?? 0
        return b1 == 22 && b2 <= 3 && b3 <= 3
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        let errorDesc = "\(error)"
        // Detect SSL handshake failures — typically caused by untrusted CA certificate
        if errorDesc.contains("ALERT_CERTIFICATE_UNKNOWN")
            || errorDesc.contains("ALERT_BAD_CERTIFICATE")
            || errorDesc.contains("ALERT_UNKNOWN_CA")
            || errorDesc.contains("sslError")
            || errorDesc.contains("CERTIFICATE_VERIFY_FAILED")
            || error is NIOSSLError {
            AxLogger.log("[MITM] TLS handshake FAILED for \(host): \(error) — client rejected our certificate. Is the CA certificate installed and trusted on the device?", level: .Error)
            recorder.recordError("error:TLS handshake failed for \(host) — CA certificate not trusted by client: \(error)")
        } else {
            AxLogger.log("[MITM] Error for \(host): \(error)", level: .Error)
            recorder.recordError("MITMHandler error for \(host): \(error)")
        }
        context.channel.close(mode: .all, promise: nil)
    }
}
