import SwiftUI
import TunnelServices

/// WebSocket detail view with chat-style frame display
public struct WebSocketDetailView: View {
    let flow: FlowRecord
    let dbGroup: TaskDatabaseGroup
    @StateObject private var vm: WebSocketDetailViewModel

    public init(flow: FlowRecord, dbGroup: TaskDatabaseGroup) {
        self.flow = flow
        self.dbGroup = dbGroup
        _vm = StateObject(wrappedValue: WebSocketDetailViewModel(flowId: flow.flowId, db: dbGroup.decoded))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("\(flow.protocolName)  \(flow.host)\(flow.searchKey2)")
                        .font(.system(size: 14, weight: .medium))
                    Text(flow.summary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let duration = flow.durationMs {
                    Text(String(format: "%.1fs", duration / 1000))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            // Frame list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(vm.frames.enumerated()), id: \.offset) { _, frame in
                        frameView(frame)
                    }
                    if vm.hasMore {
                        ProgressView()
                            .onAppear { vm.loadMore() }
                    }
                }
                .padding()
            }
        }
        .onAppear { vm.loadFrames() }
        .navigationTitle("WebSocket")
    }

    @ViewBuilder
    private func frameView(_ frame: DecodedEntry) -> some View {
        let isClose = frame.decodedType == "close"
        let isPingPong = frame.decodedType == "ping" || frame.decodedType == "pong"

        if isClose {
            HStack {
                Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                Text("CLOSE (\(frame.searchText ?? ""))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
            }
        } else if isPingPong {
            Text(frame.decodedType.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
        } else {
            let text = frame.searchText
                ?? (frame.decodedType == "binary" ? "[Binary: \(frame.decodedSize) bytes]" : "[No data]")
            MessageBubble(
                text: String(text.prefix(500)),
                isOutbound: frame.direction == 0,
                timestamp: formatTimestamp(frame.decodedAt),
                type: frame.decodedType
            )
        }
    }

    private func formatTimestamp(_ ts: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt.string(from: date)
    }
}
