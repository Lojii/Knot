import Foundation
import NIO
import NIOHTTP1
import KnotStorage

/// Pipeline handler that checks Map Local and Breakpoint rules before
/// requests reach HTTPCaptureHandler. Inserted between ConnectHandler
/// and HTTPCaptureHandler in the pipeline.
///
/// Map Local: if a request matches a Map Local rule, respond with local
/// file content and do NOT forward to HTTPCaptureHandler.
///
/// Breakpoint: (stub for Step 5) if a request matches a breakpoint rule,
/// pause the pipeline and notify UI.
public final class RuleInterceptor: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private let task: CaptureTask
    private let recorder: SessionRecorder
    private let isSSL: Bool
    private var pendingHead: HTTPRequestHead?
    private var pendingBody: ByteBuffer?
    private var isIntercepted = false  // true when Map Local is responding

    public init(task: CaptureTask, recorder: SessionRecorder, isSSL: Bool) {
        self.task = task
        self.recorder = recorder
        self.isSSL = isSSL
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            pendingHead = head
            pendingBody = nil
            isIntercepted = false

            // Check Map Local rules
            if let rule = matchMapLocal(head: head) {
                isIntercepted = true
                respondWithLocalFile(context: context, head: head, rule: rule)
                return
            }

            // No rule matched — pass through to HTTPCaptureHandler
            context.fireChannelRead(data)

        case .body:
            if isIntercepted { return }  // Swallow body if Map Local is responding
            context.fireChannelRead(data)

        case .end:
            if isIntercepted {
                isIntercepted = false
                return  // Map Local already sent response
            }
            context.fireChannelRead(data)
        }
    }

    // MARK: - Map Local

    private func matchMapLocal(head: HTTPRequestHead) -> MapLocalRule? {
        let rules = task.mapLocalRules.filter { $0.enabled }
        let fullURL: String
        if isSSL {
            let host = head.headers["Host"].first ?? ""
            fullURL = "https://\(host)\(head.uri)"
        } else {
            fullURL = head.uri  // For plain HTTP, URI is already full URL
        }

        for rule in rules {
            if matchesPattern(url: fullURL, pattern: rule.urlPattern) {
                if let method = rule.method, !method.isEmpty {
                    if head.method.rawValue.uppercased() != method.uppercased() {
                        continue
                    }
                }
                return rule
            }
        }
        return nil
    }

    private func matchesPattern(url: String, pattern: String) -> Bool {
        // Convert wildcard pattern to regex
        // * matches any characters, ? matches single character
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        let regex = "^" + escaped + "$"
        return url.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func respondWithLocalFile(context: ChannelHandlerContext, head: HTTPRequestHead, rule: MapLocalRule) {
        // Record the intercepted request
        recorder.recordRequestHead(head, localAddress: context.channel.remoteAddress, isSSL: isSSL)
        recorder.session.schemes = isSSL ? "Https" : "Http"

        // Read local file
        let bodyData: Data
        if !rule.responseFile.isEmpty, FileManager.default.fileExists(atPath: rule.responseFile) {
            bodyData = FileManager.default.contents(atPath: rule.responseFile) ?? Data()
        } else {
            bodyData = Data()
        }

        // Build response
        let status = HTTPResponseStatus(statusCode: rule.statusCode)
        var headers = HTTPHeaders()
        headers.add(name: "content-length", value: "\(bodyData.count)")
        headers.add(name: "x-knot-map-local", value: "true")

        // Parse custom headers from JSON string
        if !rule.responseHeaders.isEmpty,
           let jsonData = rule.responseHeaders.data(using: .utf8),
           let headerDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
            for (key, value) in headerDict {
                headers.replaceOrAdd(name: key, value: value)
            }
        }

        // Detect content type from file extension if not set
        if headers["Content-Type"].isEmpty {
            let ext = (rule.responseFile as NSString).pathExtension.lowercased()
            let mime: String
            switch ext {
            case "json": mime = "application/json"
            case "html", "htm": mime = "text/html"
            case "xml": mime = "application/xml"
            case "js": mime = "application/javascript"
            case "css": mime = "text/css"
            case "png": mime = "image/png"
            case "jpg", "jpeg": mime = "image/jpeg"
            case "gif": mime = "image/gif"
            case "svg": mime = "image/svg+xml"
            case "txt": mime = "text/plain"
            default: mime = "application/octet-stream"
            }
            headers.add(name: "content-type", value: mime)
        }

        let responseHead = HTTPResponseHead(version: head.version, status: status, headers: headers)

        // Record response
        recorder.recordResponseHead(responseHead)
        recorder.addProtoFlag(.keepAlive)

        // Write response to client
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)

        if !bodyData.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: bodyData.count)
            buffer.writeBytes(bodyData)
            recorder.recordResponseBody(buffer)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        recorder.recordClosed()

        AxLogger.log("[RuleInterceptor] Map Local: \(head.method) \(head.uri) → \(rule.responseFile) (\(status.code))", level: .Info)
    }

    // MARK: - Error

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
    }
}
