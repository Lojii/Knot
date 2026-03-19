import SwiftUI
import TunnelServices

/// HTTP/H2/H3 detail view with Request/Response/Overview tabs
public struct HTTPDetailView: View {
    let flow: FlowRecord
    let dbGroup: TaskDatabaseGroup
    @State private var selectedTab = 0

    public init(flow: FlowRecord, dbGroup: TaskDatabaseGroup) {
        self.flow = flow
        self.dbGroup = dbGroup
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Request").tag(0)
                Text("Response").tag(1)
                Text("Overview").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch selectedTab {
            case 0: requestView
            case 1: responseView
            case 2: overviewView
            default: EmptyView()
            }
        }
        .navigationTitle("\(flow.searchKey1) \(flow.host)")
    }

    private var requestView: some View {
        List {
            Section("请求行") {
                Text("\(flow.searchKey1) \(flow.searchKey2) \(flow.metadata["httpVersion"] as? String ?? "")")
                    .font(.system(.body, design: .monospaced))
            }
            Section("请求头") {
                headersView(key: "reqHeaders")
            }
            Section("请求体") {
                bodyPreview(direction: 0)
            }
        }
    }

    private var responseView: some View {
        List {
            Section("状态行") {
                Text("\(flow.metadata["httpVersion"] as? String ?? "") \(flow.searchKey3)")
                    .font(.system(.body, design: .monospaced))
            }
            Section("响应头") {
                headersView(key: "rspHeaders")
            }
            Section("响应体") {
                bodyPreview(direction: 1)
            }
        }
    }

    private var overviewView: some View {
        List {
            Section("基本信息") {
                LabeledContent("协议", value: flow.protocolName)
                LabeledContent("Host", value: flow.host)
                LabeledContent("状态码", value: flow.searchKey3)
                LabeledContent("Content-Type", value: flow.searchKey4)
                if let duration = flow.durationMs {
                    LabeledContent("耗时", value: String(format: "%.0fms", duration))
                }
                LabeledContent("上传", value: formatBytes(flow.uploadBytes))
                LabeledContent("下载", value: formatBytes(flow.downloadBytes))
            }
            Section("时间线") {
                TimingWaterfallView(flow: flow)
            }
        }
    }

    @ViewBuilder
    private func headersView(key: String) -> some View {
        if let headers = flow.metadata[key] as? [[String: String]] {
            ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                if let name = header.keys.first, let value = header[name] {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(value)
                            .font(.system(size: 13, design: .monospaced))
                    }
                }
            }
        } else {
            Text("无数据")
                .foregroundColor(.secondary)
        }
    }

    private func bodyPreview(direction: Int) -> some View {
        Group {
            if let entry = try? DecodedEntryDAO.find(db: dbGroup.decoded, flowId: flow.flowId, direction: direction) {
                if let text = entry.searchText, !text.isEmpty {
                    Text(String(text.prefix(2000)))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                } else if let data = entry.inlineData {
                    Text("[\(formatBytes(Int64(data.count))) binary data]")
                        .foregroundColor(.secondary)
                } else {
                    Text("[\(formatBytes(entry.decodedSize))]")
                        .foregroundColor(.secondary)
                }
            } else {
                Text("无数据")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
