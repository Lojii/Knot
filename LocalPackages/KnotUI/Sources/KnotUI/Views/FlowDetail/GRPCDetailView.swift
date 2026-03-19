import SwiftUI
import TunnelServices

/// gRPC detail view with Request/Response/Headers tabs
public struct GRPCDetailView: View {
    let flow: FlowRecord
    let dbGroup: TaskDatabaseGroup
    @State private var selectedTab = 0
    @State private var requestEntries: [DecodedEntry] = []
    @State private var responseEntries: [DecodedEntry] = []

    public init(flow: FlowRecord, dbGroup: TaskDatabaseGroup) {
        self.flow = flow
        self.dbGroup = dbGroup
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Request").tag(0)
                Text("Response").tag(1)
                Text("Headers").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch selectedTab {
            case 0: messagesView(entries: requestEntries, label: "Request")
            case 1: messagesView(entries: responseEntries, label: "Response")
            case 2: headersView
            default: EmptyView()
            }
        }
        .onAppear { loadEntries() }
        .navigationTitle("\(flow.searchKey2)/\(flow.searchKey1)")
    }

    private func messagesView(entries: [DecodedEntry], label: String) -> some View {
        List {
            if entries.isEmpty {
                Text("无 \(label) 数据")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                    Section("Message #\(idx)") {
                        if let text = entry.searchText, !text.isEmpty {
                            Text(String(text.prefix(2000)))
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        } else {
                            Text("[\(entry.decodedSize) bytes binary]")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var headersView: some View {
        List {
            Section("Request Headers") {
                headersList(key: "reqHeaders")
            }
            Section("Response Headers") {
                headersList(key: "rspHeaders")
            }
            if let trailers = flow.metadata["trailers"] as? [[String: String]], !trailers.isEmpty {
                Section("Trailers") {
                    ForEach(Array(trailers.enumerated()), id: \.offset) { _, t in
                        if let name = t.keys.first, let value = t[name] {
                            LabeledContent(name, value: value)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func headersList(key: String) -> some View {
        if let headers = flow.metadata[key] as? [[String: String]] {
            ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                if let name = header.keys.first, let value = header[name] {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                        Text(value).font(.system(size: 12, design: .monospaced))
                    }
                }
            }
        } else {
            Text("无数据").foregroundColor(.secondary)
        }
    }

    private func loadEntries() {
        let all = (try? DecodedEntryDAO.findAll(db: dbGroup.decoded, flowId: flow.flowId)) ?? []
        requestEntries = all.filter { $0.direction == 0 }
        responseEntries = all.filter { $0.direction == 1 }
    }
}
