import SwiftUI
import TunnelServices

/// Displays HTTP request timing as a waterfall chart
public struct TimingWaterfallView: View {
    let flow: FlowRecord

    public init(flow: FlowRecord) {
        self.flow = flow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let connected = flow.connectedAt {
                timingRow("Connect", from: flow.startedAt, to: connected, total: totalDuration)
            }
            if let tls = flow.tlsDoneAt, let connected = flow.connectedAt {
                timingRow("TLS", from: connected, to: tls, total: totalDuration)
            }
            if let reqEnd = flow.reqEndAt {
                let start = flow.tlsDoneAt ?? flow.connectedAt ?? flow.startedAt
                timingRow("Request", from: start, to: reqEnd, total: totalDuration)
            }
            if let rspStart = flow.rspStartAt, let reqEnd = flow.reqEndAt {
                timingRow("TTFB", from: reqEnd, to: rspStart, total: totalDuration)
            }
            if let ended = flow.endedAt, let rspStart = flow.rspStartAt {
                timingRow("Response", from: rspStart, to: ended, total: totalDuration)
            }
        }
        .padding()
    }

    private var totalDuration: TimeInterval {
        (flow.endedAt ?? flow.startedAt) - flow.startedAt
    }

    private func timingRow(_ label: String, from: TimeInterval, to: TimeInterval, total: TimeInterval) -> some View {
        let duration = to - from
        let offset = from - flow.startedAt
        let fraction = total > 0 ? duration / total : 0
        let offsetFraction = total > 0 ? offset / total : 0

        return HStack {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 60, alignment: .trailing)
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: max(geo.size.width * fraction, 2))
                    .offset(x: geo.size.width * offsetFraction)
            }
            .frame(height: 12)
            Text(String(format: "%.0fms", duration * 1000))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}
