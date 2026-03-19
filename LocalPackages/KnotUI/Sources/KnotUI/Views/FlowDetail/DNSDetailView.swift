import SwiftUI
import TunnelServices

/// DNS query/answer detail view
public struct DNSDetailView: View {
    let flow: FlowRecord

    public init(flow: FlowRecord) {
        self.flow = flow
    }

    public var body: some View {
        List {
            Section("查询信息") {
                LabeledContent("类型", value: flow.searchKey1)
                LabeledContent("域名", value: flow.searchKey2)
                LabeledContent("传输", value: (flow.metadata["transport"] as? String ?? "").uppercased())
                if let duration = flow.durationMs {
                    LabeledContent("耗时", value: String(format: "%.0fms", duration))
                }
            }

            if let questions = flow.metadata["questions"] as? [[String: Any]], !questions.isEmpty {
                Section("Questions") {
                    ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                        HStack {
                            Text(q["type"] as? String ?? "")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.blue)
                                .frame(width: 40)
                            Text(q["name"] as? String ?? "")
                                .font(.system(size: 13, design: .monospaced))
                            Spacer()
                            Text(q["class"] as? String ?? "IN")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if let answers = flow.metadata["answers"] as? [[String: Any]], !answers.isEmpty {
                Section("Answers") {
                    ForEach(Array(answers.enumerated()), id: \.offset) { _, a in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(a["type"] as? String ?? "")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                                Text(a["name"] as? String ?? "")
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                if let ttl = a["ttl"] {
                                    Text("TTL=\(ttl)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            if let data = a["data"] as? String {
                                Text("→ \(data)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }

            Section("响应") {
                LabeledContent("Response Code", value: flow.searchKey4)
                if let httpFlowId = flow.metadata["httpFlowId"] as? String {
                    LabeledContent("HTTP Flow", value: httpFlowId)
                    // Future: make this a NavigationLink to the HTTP flow
                }
            }
        }
        .navigationTitle("DNS \(flow.searchKey1)")
    }
}
