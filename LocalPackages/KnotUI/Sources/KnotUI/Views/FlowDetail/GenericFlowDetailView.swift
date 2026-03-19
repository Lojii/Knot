import SwiftUI
import TunnelServices

/// Fallback detail view for unknown protocol types
public struct GenericFlowDetailView: View {
    let flow: FlowRecord

    public init(flow: FlowRecord) {
        self.flow = flow
    }

    public var body: some View {
        List {
            Section("基本信息") {
                LabeledContent("协议", value: flow.protocolName)
                LabeledContent("Host", value: flow.host)
                LabeledContent("端口", value: "\(flow.port)")
                LabeledContent("状态", value: flow.status == .completed ? "完成" : flow.status == .failed ? "失败" : "进行中")
            }
            if !flow.summary.isEmpty {
                Section("摘要") {
                    Text(flow.summary)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .navigationTitle(flow.protocolName)
    }
}
