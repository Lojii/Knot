import Foundation
import TunnelServices

public enum ExportFormat: String, CaseIterable, Identifiable {
    case url = "URL"
    case curl = "cURL"
    case har = "HAR"
    case pcap = "PCAP"
    public var id: String { rawValue }
}

public struct ExportService {
    public init() {}

    // MARK: - FlowRecord-based export

    public func export(flows: [FlowRecord], format: ExportFormat) -> Data? {
        switch format {
        case .url:
            let urls = flows.map { Self.exportURL(flow: $0) }.joined(separator: "\n")
            return urls.data(using: .utf8)
        case .curl:
            let curls = flows.map { Self.exportCurl(flow: $0) }.joined(separator: "\n\n")
            return curls.data(using: .utf8)
        case .har, .pcap:
            return nil // Delegate to TunnelServices exporters
        }
    }

    public static func exportURL(flow: FlowRecord) -> String {
        let scheme: String
        let proto = flow.protocolName.lowercased()
        if proto.contains("https") || flow.protocolName == "H2" || flow.protocolName == "H3" {
            scheme = "https"
        } else {
            scheme = "http"
        }
        return "\(scheme)://\(flow.host)\(flow.searchKey2)"
    }

    public static func exportCurl(flow: FlowRecord) -> String {
        let url = exportURL(flow: flow)
        var parts = ["curl"]
        if flow.searchKey1 != "GET" {
            parts.append("-X \(flow.searchKey1)")
        }
        // Add headers from metadata if available
        if let headers = flow.metadata["reqHeaders"] as? [[String: String]] {
            for header in headers {
                if let name = header.keys.first, let value = header[name] {
                    parts.append("-H '\(name): \(value)'")
                }
            }
        }
        parts.append("'\(url)'")
        return parts.joined(separator: " \\\n  ")
    }
}
