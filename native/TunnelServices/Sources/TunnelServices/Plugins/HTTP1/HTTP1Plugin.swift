import Foundation
import NIO
import NIOHTTP1
import NIOHTTPCompression
import NIOExtras
import KnotStorage

/// Plugin that identifies and handles HTTP/1.x traffic.
/// Matches plain-text HTTP request lines (GET, POST, etc.) and builds the
/// necessary NIO pipeline to capture the exchange.
public final class HTTP1Plugin: ProtocolPlugin {
    public let id = "http1"
    public let displayName = "HTTP/1.x"

    private static let httpMethods = ["GET ", "POST", "PUT ", "HEAD", "OPTI", "PATC", "DELE", "TRAC", "CONN"]

    public init() {}

    // MARK: - ProtocolPlugin

    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        guard buffer.readableBytes >= 4 else { return .needMoreData(minimum: 4) }
        let prefix = buffer.getString(at: buffer.readerIndex, length: 4) ?? ""
        let isHTTP = HTTP1Plugin.httpMethods.contains(where: { prefix.hasPrefix($0.prefix(4)) })
        return isHTTP ? .yes(confidence: 90) : .no
    }

    /// Builds the HTTP/1.x capture pipeline.
    ///
    /// For plain HTTP: server-side HTTP codec + pipelining + HTTPCaptureHandler(isSSL: false)
    /// For HTTP-over-TLS (parentProtocol == "tls"): same codec stack + HTTPCaptureHandler(isSSL: true)
    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let isSSL = context.parentProtocol == "tls"
        let pipeline = context.channel.pipeline

        // Use .dropBytes: when ConnectHandler removes this decoder (to switch to
        // raw TLS or MITM), any buffered bytes (e.g., pipelined TLS ClientHello from
        // Chromium) are dropped instead of forwarded as IOData. This prevents a crash
        // where IOData reaches HTTPCaptureHandler which expects HTTPServerRequestPart.
        // The MITMHandler will receive the ClientHello via its own channelRead.
        return pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .dropBytes)),
                                   name: "http1.requestDecoder")
            .flatMap {
                pipeline.addHandler(HTTPResponseEncoder(), name: "http1.responseEncoder")
            }
            .flatMap {
                pipeline.addHandler(HTTPServerPipelineHandler(), name: "http1.pipelining")
            }
            .flatMap {
                // ConnectHandler intercepts CONNECT requests for HTTPS tunneling;
                // non-CONNECT requests pass through to HTTPCaptureHandler.
                let connectHandler = ConnectHandler(task: context.task, recorder: context.recorder)
                return pipeline.addHandler(connectHandler, name: "http1.connect")
            }
            .flatMap {
                pipeline.addHandler(
                    HTTPCaptureHandler(recorder: context.recorder, isSSL: isSSL),
                    name: "http1.captureHandler"
                )
            }
    }

    /// Returns an `HTTPRecorder` to capture this HTTP/1.x flow.
    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        let host = context.metadata.innerHost
            ?? context.metadata.sni
            ?? (context.channel.remoteAddress?.description ?? "unknown")
        let port = context.metadata.innerPort ?? context.task.localPort
        return HTTPRecorder(flowId: flowId, host: host, port: port)
    }
}
