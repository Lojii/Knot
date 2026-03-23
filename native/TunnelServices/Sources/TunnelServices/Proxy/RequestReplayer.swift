//
//  RequestReplayer.swift
//  TunnelServices
//
//  Replay captured HTTP requests and return results.
//  Also provides Mock/Map Local/Map Remote capabilities.
//

import Foundation
import NIO
import NIOHTTP1
import NIOSSL

// MARK: - Request Replay

public class RequestReplayer {

    public struct ReplayResult {
        public let statusCode: Int
        public let headers: [(String, String)]
        public let body: Data
        public let latencyMs: Int
    }

    /// Replay a captured session's request.
    public static func replay(session: ProxySession, modifications: RequestModification? = nil) throws -> ReplayResult {
        let url = session.getFullUrl()
        guard let urlObj = URL(string: url) else {
            throw ReplayError.invalidURL(url)
        }

        var request = URLRequest(url: urlObj)
        request.httpMethod = modifications?.method ?? (session.methods.isEmpty ? "GET" : session.methods)
        request.timeoutInterval = 30

        // Restore original headers
        let headersJSON = session.reqHeads
        if let data = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            for header in headers {
                for (key, value) in header {
                    if let override = modifications?.headers?[key] {
                        request.setValue(override, forHTTPHeaderField: key)
                    } else {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                }
            }
        }

        // Apply header modifications
        modifications?.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Body
        if let modBody = modifications?.body {
            request.httpBody = modBody
        } else if session.reqBody != "" {
            request.httpBody = FileManager.default.contents(atPath: session.reqBody)
        }

        // Override host if specified
        if let newHost = modifications?.host, var components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false) {
            components.host = newHost
            if let newURL = components.url { request.url = newURL }
        }

        // Execute synchronously
        let semaphore = DispatchSemaphore(value: 0)
        var result: ReplayResult?
        var error: Error?
        let start = CFAbsoluteTimeGetCurrent()

        let task = URLSession.shared.dataTask(with: request) { data, response, err in
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let err = err {
                error = err
            } else if let httpResponse = response as? HTTPURLResponse {
                let headers = httpResponse.allHeaderFields.map { ("\($0.key)", "\($0.value)") }
                result = ReplayResult(
                    statusCode: httpResponse.statusCode,
                    headers: headers,
                    body: data ?? Data(),
                    latencyMs: elapsed
                )
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = error { throw error }
        guard let result = result else { throw ReplayError.noResponse }
        return result
    }

    public struct RequestModification {
        public var method: String?
        public var headers: [String: String]?
        public var body: Data?
        public var host: String?

        public init(method: String? = nil, headers: [String: String]? = nil, body: Data? = nil, host: String? = nil) {
            self.method = method; self.headers = headers; self.body = body; self.host = host
        }
    }

    public enum ReplayError: Error {
        case invalidURL(String)
        case noResponse
    }
}

// MARK: - Mock Rule

public struct MockRule: Codable {
    public var id: String
    public var urlPattern: String        // regex or wildcard
    public var method: String?           // nil = match all
    public var responseStatusCode: Int
    public var responseHeaders: [String: String]
    public var responseBody: String      // or file path
    public var latencyMs: Int
    public var enabled: Bool

    public init(urlPattern: String, statusCode: Int = 200, body: String = "", latency: Int = 0) {
        self.id = UUID().uuidString
        self.urlPattern = urlPattern
        self.method = nil
        self.responseStatusCode = statusCode
        self.responseHeaders = ["content-type": "application/json"]
        self.responseBody = body
        self.latencyMs = latency
        self.enabled = true
    }

    public func matches(url: String, httpMethod: String) -> Bool {
        guard enabled else { return false }
        if let m = method, m.uppercased() != httpMethod.uppercased() { return false }

        // Simple wildcard matching (* = any)
        let pattern = urlPattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
        return url.range(of: "^\(pattern)$", options: .regularExpression) != nil
    }
}

// MARK: - Mock Rule Manager

public class MockRuleManager {
    public static let shared = MockRuleManager()

    private var rules = [MockRule]()
    private let lock = NSLock()

    public func addRule(_ rule: MockRule) {
        lock.lock(); rules.append(rule); lock.unlock()
    }

    public func removeRule(id: String) {
        lock.lock(); rules.removeAll { $0.id == id }; lock.unlock()
    }

    public func allRules() -> [MockRule] {
        lock.lock(); defer { lock.unlock() }; return rules
    }

    /// Find the first matching mock rule for the given URL and method.
    public func match(url: String, method: String) -> MockRule? {
        lock.lock(); defer { lock.unlock() }
        return rules.first { $0.matches(url: url, httpMethod: method) }
    }

    /// Clear all rules.
    public func clearAll() {
        lock.lock(); rules.removeAll(); lock.unlock()
    }
}

// MARK: - Legacy Map Remote Rule (superseded by KnotStorage.MapRemoteRule)

@available(*, deprecated, renamed: "KnotStorage.MapRemoteRule")
public struct LegacyMapRemoteRule: Codable {
    public var id: String
    public var sourcePattern: String     // URL pattern to match
    public var targetHost: String        // Redirect to this host
    public var targetPort: Int?          // Optional port override
    public var targetPath: String?       // Optional path override
    public var enabled: Bool

    public init(sourcePattern: String, targetHost: String) {
        self.id = UUID().uuidString
        self.sourcePattern = sourcePattern
        self.targetHost = targetHost
        self.targetPort = nil
        self.targetPath = nil
        self.enabled = true
    }
}

// MARK: - Legacy Map Local Rule (superseded by KnotStorage.MapLocalRule)

@available(*, deprecated, renamed: "KnotStorage.MapLocalRule")
public struct LegacyMapLocalRule: Codable {
    public var id: String
    public var urlPattern: String        // URL pattern to match
    public var localFilePath: String     // Path to local file
    public var contentType: String       // MIME type
    public var statusCode: Int
    public var enabled: Bool

    public init(urlPattern: String, localFilePath: String, contentType: String = "application/json") {
        self.id = UUID().uuidString
        self.urlPattern = urlPattern
        self.localFilePath = localFilePath
        self.contentType = contentType
        self.statusCode = 200
        self.enabled = true
    }
}
