//
//  BreakpointHandler.swift
//  TunnelServices
//
//  Request/Response breakpoints and automatic rewrite rules.
//  Pauses pipeline execution for manual editing or applies rules automatically.
//
//  Netty inspiration: ChannelDuplexHandler interception pattern.
//  Charles Proxy inspiration: Breakpoints, Rewrite, Map Remote.
//

import Foundation
import NIO
import NIOHTTP1

// MARK: - Breakpoint Rule

public struct BreakpointRule: Codable {
    public var id: String
    public var urlPattern: String
    public var method: String?           // nil = match all
    public var breakOnRequest: Bool
    public var breakOnResponse: Bool
    public var enabled: Bool

    public init(urlPattern: String, breakOnRequest: Bool = true, breakOnResponse: Bool = false) {
        self.id = UUID().uuidString
        self.urlPattern = urlPattern
        self.method = nil
        self.breakOnRequest = breakOnRequest
        self.breakOnResponse = breakOnResponse
        self.enabled = true
    }

    func matches(url: String, httpMethod: String) -> Bool {
        guard enabled else { return false }
        if let m = method, m.uppercased() != httpMethod.uppercased() { return false }
        let pattern = urlPattern.replacingOccurrences(of: ".", with: "\\.").replacingOccurrences(of: "*", with: ".*")
        return url.range(of: "^\(pattern)$", options: .regularExpression) != nil
    }
}

// MARK: - Rewrite Rule

public struct RewriteRule: Codable {
    public var id: String
    public var urlPattern: String
    public var enabled: Bool

    // Request modifications
    public var addRequestHeaders: [String: String]?
    public var removeRequestHeaders: [String]?
    public var requestBodyReplace: [StringReplace]?

    // Response modifications
    public var overrideStatusCode: Int?
    public var addResponseHeaders: [String: String]?
    public var removeResponseHeaders: [String]?
    public var responseBodyReplace: [StringReplace]?

    public struct StringReplace: Codable {
        public var find: String
        public var replace: String
    }

    public init(urlPattern: String) {
        self.id = UUID().uuidString
        self.urlPattern = urlPattern
        self.enabled = true
    }

    func matches(url: String) -> Bool {
        guard enabled else { return false }
        let pattern = urlPattern.replacingOccurrences(of: ".", with: "\\.").replacingOccurrences(of: "*", with: ".*")
        return url.range(of: "^\(pattern)$", options: .regularExpression) != nil
    }
}

// MARK: - Breakpoint Manager

public class BreakpointManager {
    public static let shared = BreakpointManager()

    private var breakpointRules = [BreakpointRule]()
    private var rewriteRules = [RewriteRule]()
    private let lock = NSLock()

    /// Callback type for breakpoint pause. The closure receives the data and
    /// must call the resume closure with (optionally modified) data.
    public typealias BreakpointCallback = (_ data: BreakpointData, _ resume: @escaping (BreakpointData) -> Void) -> Void

    /// Set by the UI layer to handle breakpoint pauses.
    public var onBreakpoint: BreakpointCallback?

    // MARK: - Rule Management

    public func addBreakpoint(_ rule: BreakpointRule) {
        lock.lock(); breakpointRules.append(rule); lock.unlock()
    }
    public func addRewrite(_ rule: RewriteRule) {
        lock.lock(); rewriteRules.append(rule); lock.unlock()
    }
    public func removeBreakpoint(id: String) {
        lock.lock(); breakpointRules.removeAll { $0.id == id }; lock.unlock()
    }
    public func removeRewrite(id: String) {
        lock.lock(); rewriteRules.removeAll { $0.id == id }; lock.unlock()
    }
    public func allBreakpoints() -> [BreakpointRule] {
        lock.lock(); defer { lock.unlock() }; return breakpointRules
    }
    public func allRewrites() -> [RewriteRule] {
        lock.lock(); defer { lock.unlock() }; return rewriteRules
    }

    // MARK: - Matching

    func matchBreakpoint(url: String, method: String) -> BreakpointRule? {
        lock.lock(); defer { lock.unlock() }
        return breakpointRules.first { $0.matches(url: url, httpMethod: method) }
    }

    func matchRewrite(url: String) -> RewriteRule? {
        lock.lock(); defer { lock.unlock() }
        return rewriteRules.first { $0.matches(url: url) }
    }
}

// MARK: - Breakpoint Data

public struct BreakpointData {
    public enum Phase { case request, response }
    public let phase: Phase
    public var url: String
    public var method: String
    public var statusCode: Int?
    public var headers: [(String, String)]
    public var body: Data?

    public init(phase: Phase, url: String, method: String = "", statusCode: Int? = nil,
                headers: [(String, String)] = [], body: Data? = nil) {
        self.phase = phase; self.url = url; self.method = method
        self.statusCode = statusCode; self.headers = headers; self.body = body
    }
}

// MARK: - Rewrite Handler (automatic)

/// Automatically applies rewrite rules to requests and responses.
/// Insert in pipeline before HTTPCaptureHandler.
public final class RewriteHandler: ChannelDuplexHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias InboundOut = HTTPServerRequestPart
    public typealias OutboundIn = HTTPServerResponsePart
    public typealias OutboundOut = HTTPServerResponsePart

    private var matchedRule: RewriteRule?
    private var url = ""

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var part = unwrapInboundIn(data)

        switch part {
        case .head(var head):
            url = head.uri
            matchedRule = BreakpointManager.shared.matchRewrite(url: url)

            if let rule = matchedRule {
                // Add headers
                rule.addRequestHeaders?.forEach { key, value in
                    head.headers.replaceOrAdd(name: key, value: value)
                }
                // Remove headers
                rule.removeRequestHeaders?.forEach { key in
                    head.headers.remove(name: key)
                }
                context.fireChannelRead(wrapInboundOut(.head(head)))
                return
            }
            context.fireChannelRead(data)

        case .body(var body):
            if let rule = matchedRule, let replacements = rule.requestBodyReplace {
                if var str = body.readString(length: body.readableBytes) {
                    for r in replacements {
                        str = str.replacingOccurrences(of: r.find, with: r.replace)
                    }
                    var newBuffer = context.channel.allocator.buffer(capacity: str.utf8.count)
                    newBuffer.writeString(str)
                    context.fireChannelRead(wrapInboundOut(.body(newBuffer)))
                    return
                }
            }
            context.fireChannelRead(data)

        case .end:
            context.fireChannelRead(data)
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let part = unwrapOutboundIn(data)

        switch part {
        case .head(var head):
            if let rule = matchedRule {
                // Override status code
                if let code = rule.overrideStatusCode {
                    head = HTTPResponseHead(version: head.version, status: .custom(code: UInt(code), reasonPhrase: ""))
                }
                // Add headers
                rule.addResponseHeaders?.forEach { key, value in
                    head.headers.replaceOrAdd(name: key, value: value)
                }
                // Remove headers
                rule.removeResponseHeaders?.forEach { key in
                    head.headers.remove(name: key)
                }
                context.write(wrapOutboundOut(.head(head)), promise: promise)
                return
            }
            context.write(data, promise: promise)

        case .body(var ioData):
            if let rule = matchedRule, let replacements = rule.responseBodyReplace {
                if case .byteBuffer(var body) = ioData,
                   var str = body.readString(length: body.readableBytes) {
                    for r in replacements {
                        str = str.replacingOccurrences(of: r.find, with: r.replace)
                    }
                    var newBuffer = context.channel.allocator.buffer(capacity: str.utf8.count)
                    newBuffer.writeString(str)
                    context.write(wrapOutboundOut(.body(.byteBuffer(newBuffer))), promise: promise)
                    return
                }
            }
            context.write(data, promise: promise)

        case .end:
            context.write(data, promise: promise)
        }
    }
}
