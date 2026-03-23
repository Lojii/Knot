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
    private var breakpointPromise: EventLoopPromise<CaptureTask.BreakpointAction>?
    private var breakpointFlowId: String?
    private var isBreakpointPaused = false

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

            let host = head.headers["Host"].first ?? ""

            // 1. Check Block List — drop request with 403
            if isBlocked(host: host) {
                isIntercepted = true
                let resp = HTTPResponseHead(version: .http1_1, status: .forbidden)
                context.write(wrapOutboundOut(.head(resp)), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
                AxLogger.log("[RuleInterceptor] Blocked: \(host)", level: .Info)
                return
            }

            // 2. Check Allow List — if non-empty, only allow matching hosts
            if !task.allowList.isEmpty && !isAllowed(host: host) {
                // Not in allow list — pass through without interception
                context.fireChannelRead(data)
                return
            }

            // 3. Check Map Local rules
            if let rule = matchMapLocal(head: head) {
                isIntercepted = true
                respondWithLocalFile(context: context, head: head, rule: rule)
                return
            }

            // 4. Check Map Remote rules — rewrite URL and pass through
            if let (rule, modifiedHead) = matchAndApplyMapRemote(head: head) {
                AxLogger.log("[RuleInterceptor] Map Remote: \(head.uri) → \(modifiedHead.uri)", level: .Info)
                // 5. Apply No Caching to the rewritten request if enabled
                if task.noCachingEnabled {
                    var noCacheHead = modifiedHead
                    noCacheHead.headers.remove(name: "If-Modified-Since")
                    noCacheHead.headers.remove(name: "If-None-Match")
                    noCacheHead.headers.replaceOrAdd(name: "Pragma", value: "no-cache")
                    noCacheHead.headers.replaceOrAdd(name: "Cache-Control", value: "no-cache")
                    context.fireChannelRead(NIOAny(HTTPServerRequestPart.head(noCacheHead)))
                } else {
                    context.fireChannelRead(NIOAny(HTTPServerRequestPart.head(modifiedHead)))
                }
                return
            }

            // 5. No Caching: strip cache headers from request
            if task.noCachingEnabled {
                var modified = head
                modified.headers.remove(name: "If-Modified-Since")
                modified.headers.remove(name: "If-None-Match")
                modified.headers.replaceOrAdd(name: "Pragma", value: "no-cache")
                modified.headers.replaceOrAdd(name: "Cache-Control", value: "no-cache")
                context.fireChannelRead(NIOAny(HTTPServerRequestPart.head(modified)))
                return
            }

            // 6. Check Breakpoint rules (on request)
            if let rule = matchBreakpoint(head: head) {
                if rule.breakOn == "request" || rule.breakOn == "both" {
                    isBreakpointPaused = true
                    pauseForBreakpoint(context: context, head: head, rule: rule)
                    return
                }
            }

            // No rule matched — pass through to HTTPCaptureHandler
            context.fireChannelRead(data)

        case .body:
            if isIntercepted || isBreakpointPaused { return }  // Swallow body if intercepted or paused
            context.fireChannelRead(data)

        case .end:
            if isIntercepted {
                isIntercepted = false
                return  // Map Local already sent response
            }
            if isBreakpointPaused { return }  // Swallow end while breakpoint is paused
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

    // MARK: - Map Remote

    private func matchAndApplyMapRemote(head: HTTPRequestHead) -> (MapRemoteRule, HTTPRequestHead)? {
        let rules = task.mapRemoteRules.filter { $0.enabled }
        let host = head.headers["Host"].first ?? ""
        let fullURL = isSSL ? "https://\(host)\(head.uri)" : head.uri

        for rule in rules {
            if let method = rule.method, !method.isEmpty,
               head.method.rawValue.uppercased() != method.uppercased() {
                continue
            }
            if matchesPattern(url: fullURL, pattern: rule.urlPattern) {
                var modified = head
                // Parse current URL
                guard var components = URLComponents(string: fullURL) else { continue }

                // Apply replacements (empty/nil = keep original)
                if let scheme = rule.replaceScheme, !scheme.isEmpty { components.scheme = scheme }
                if let rHost = rule.replaceHost, !rHost.isEmpty { components.host = rHost }
                if let port = rule.replacePort, port > 0 { components.port = port }
                if let path = rule.replacePath, !path.isEmpty { components.path = path }

                // Update Host header
                if let newHost = components.host {
                    modified.headers.replaceOrAdd(name: "Host", value: components.port != nil ? "\(newHost):\(components.port!)" : newHost)
                }

                // Update URI
                if isSSL {
                    modified.uri = components.path + (components.query.map { "?\($0)" } ?? "")
                } else {
                    modified.uri = components.string ?? head.uri
                }

                return (rule, modified)
            }
        }
        return nil
    }

    // MARK: - Allow/Block List

    private func isBlocked(host: String) -> Bool {
        task.blockList.contains { matchesPattern(url: host, pattern: $0) }
    }

    private func isAllowed(host: String) -> Bool {
        task.allowList.contains { matchesPattern(url: host, pattern: $0) }
    }

    // MARK: - Breakpoint

    private func matchBreakpoint(head: HTTPRequestHead) -> BreakpointRule? {
        let rules = task.breakpointRules.filter { $0.enabled }
        let host = head.headers["Host"].first ?? ""
        let fullURL = isSSL ? "https://\(host)\(head.uri)" : head.uri

        for rule in rules {
            if matchesPattern(url: fullURL, pattern: rule.urlPattern) {
                if let method = rule.method, !method.isEmpty,
                   head.method.rawValue.uppercased() != method.uppercased() {
                    continue
                }
                return rule
            }
        }
        return nil
    }

    private func pauseForBreakpoint(context: ChannelHandlerContext, head: HTTPRequestHead, rule: BreakpointRule) {
        let flowId = UUID().uuidString
        breakpointFlowId = flowId

        let promise = context.eventLoop.makePromise(of: CaptureTask.BreakpointAction.self)
        breakpointPromise = promise

        // Record request
        recorder.recordRequestHead(head, localAddress: context.channel.remoteAddress, isSSL: isSSL)

        // Notify UI via LiveBridge
        let host = head.headers["Host"].first ?? ""
        task.liveBridge?.onBreakpointHit?([
            "flowId": flowId,
            "method": head.method.rawValue,
            "url": isSSL ? "https://\(host)\(head.uri)" : head.uri,
            "headers": Dictionary(uniqueKeysWithValues: head.headers.map { ($0.name, $0.value) }),
            "breakType": "request"
        ])

        // Register callback for API resume
        task.registerBreakpointCallback(flowId: flowId) { [weak self] action in
            context.eventLoop.execute {
                promise.succeed(action)
            }
        }

        // Handle resume
        promise.futureResult.whenComplete { [weak self] result in
            guard let self = self else { return }
            self.isBreakpointPaused = false
            self.breakpointFlowId = nil
            self.breakpointPromise = nil

            switch result {
            case .success(.execute(let modifiedHead)):
                let finalHead = modifiedHead ?? head
                context.fireChannelRead(NIOAny(HTTPServerRequestPart.head(finalHead)))
            case .success(.cancel):
                context.fireChannelRead(NIOAny(HTTPServerRequestPart.head(head)))
            case .success(.abort):
                let resp = HTTPResponseHead(version: .http1_1, status: .serviceUnavailable)
                context.write(self.wrapOutboundOut(.head(resp)), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                self.recorder.recordClosed()
            case .failure:
                context.fireChannelRead(NIOAny(HTTPServerRequestPart.head(head)))
            }
        }

        // Timeout: auto-cancel after 30 seconds
        context.eventLoop.scheduleTask(in: .seconds(30)) { [weak self] in
            if self?.breakpointFlowId == flowId {
                promise.succeed(.cancel)
            }
        }

        AxLogger.log("[RuleInterceptor] Breakpoint hit: \(head.method) \(head.uri)", level: .Warning)
    }

    // MARK: - Error

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.fireErrorCaught(error)
    }
}
