import SwiftUI
import TunnelServices

struct CurrentTaskView: View {
    let task: CaptureTask?
    let onTap: () -> Void

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .binary
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            if let task = task {
                taskContent(task)
            } else {
                emptyContent
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func taskContent(_ task: CaptureTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(task.ruleName.isEmpty ? "当前任务" : task.ruleName, systemImage: "record.circle")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                statItem(
                    label: "拦截",
                    value: "\(Int(task.interceptCount))"
                )
                statItem(
                    label: "上传",
                    value: byteFormatter.string(fromByteCount: task.uploadTraffic)
                )
                statItem(
                    label: "下载",
                    value: byteFormatter.string(fromByteCount: task.downloadFlow)
                )
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyContent: some View {
        HStack {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
            Text("暂无任务")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
