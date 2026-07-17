import Foundation
import NIOHTTP1

/// Helpers for validating the per-session bearer token on API and WebSocket requests.
enum RequestAuth {

    /// Extract the `token` query parameter from a request URI, if present.
    static func tokenFromURI(_ uri: String) -> String? {
        guard let q = uri.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0] == "token" {
                return String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return nil
    }

    /// Returns true if the request carries the expected token, either as a
    /// `Authorization: Bearer <token>` header or a `?token=` query parameter.
    static func isAuthorized(headers: HTTPHeaders, uri: String, expected: String) -> Bool {
        if let auth = headers.first(name: "authorization"),
           auth.hasPrefix("Bearer "),
           String(auth.dropFirst("Bearer ".count)) == expected {
            return true
        }
        return tokenFromURI(uri) == expected
    }
}
