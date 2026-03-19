import SwiftUI
import TunnelServices

/// Unified cell for displaying any protocol's Flow in the list
public struct FlowCell: View {
    let flow: FlowRecord

    public init(flow: FlowRecord) {
        self.flow = flow
    }

    public var body: some View {
        HStack(spacing: 8) {
            ProtocolBadge(protocolName: flow.protocolName, searchKey1: flow.searchKey1)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(flow.host)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(flow.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                statusView
                trafficView
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch flow.protocolName {
        case "HTTP", "HTTPS", "H2", "H3":
            if !flow.searchKey3.isEmpty {
                Text(flow.searchKey3)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(httpStatusColor(flow.searchKey3))
            }
        case "WS", "WSS":
            Text("↑\(flow.searchKey3)") // total frames
                .font(.system(size: 11))
                .foregroundColor(.purple)
        case "DNS":
            Text(flow.searchKey3.isEmpty ? flow.searchKey4 : flow.searchKey3)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        case "gRPC":
            Text(flow.searchKey4) // grpc message
                .font(.system(size: 11))
                .foregroundColor(flow.searchKey3 == "0" ? .green : .red)
        default:
            EmptyView()
        }
    }

    private var trafficView: some View {
        HStack(spacing: 2) {
            if flow.durationMs != nil {
                Text(formatDuration(flow.durationMs!))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func httpStatusColor(_ status: String) -> Color {
        guard let code = Int(status) else { return .gray }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .gray
        }
    }

    private func formatDuration(_ ms: Double) -> String {
        if ms < 1000 { return String(format: "%.0fms", ms) }
        return String(format: "%.1fs", ms / 1000)
    }
}
