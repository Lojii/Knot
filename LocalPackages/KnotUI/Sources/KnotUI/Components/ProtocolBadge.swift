import SwiftUI

/// Displays a protocol-specific icon and method badge
public struct ProtocolBadge: View {
    let protocolName: String
    let searchKey1: String  // method for HTTP, subprotocol for WS, queryType for DNS, etc.

    public init(protocolName: String, searchKey1: String = "") {
        self.protocolName = protocolName
        self.searchKey1 = searchKey1
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 12))
                .frame(width: 16)
            if !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(badgeColor)
                    .cornerRadius(3)
            }
        }
    }

    private var iconName: String {
        switch protocolName {
        case "HTTP", "HTTPS", "H2", "H3": return "globe"
        case "WS", "WSS": return "arrow.up.arrow.down"
        case "DNS": return "magnifyingglass"
        case "gRPC": return "arrow.triangle.branch"
        default: return "network"
        }
    }

    private var iconColor: Color {
        switch protocolName {
        case "HTTP", "HTTPS", "H2", "H3": return .blue
        case "WS", "WSS": return .purple
        case "DNS": return .cyan
        case "gRPC": return .orange
        default: return .gray
        }
    }

    private var badgeText: String {
        switch protocolName {
        case "HTTP", "HTTPS", "H2", "H3": return searchKey1.uppercased() // GET, POST, etc.
        case "WS", "WSS": return "WS"
        case "DNS": return searchKey1.uppercased() // A, AAAA, etc.
        case "gRPC": return "gRPC"
        case "H2": return "H2"
        case "H3": return "H3"
        default: return protocolName
        }
    }

    private var badgeColor: Color {
        switch protocolName {
        case "HTTP", "HTTPS", "H2", "H3":
            switch searchKey1.uppercased() {
            case "GET": return .blue
            case "POST": return .green
            case "PUT": return .orange
            case "DELETE": return .red
            case "PATCH": return .purple
            default: return .gray
            }
        case "WS", "WSS": return .purple
        case "DNS": return .cyan
        case "gRPC": return .orange
        default: return .gray
        }
    }
}
