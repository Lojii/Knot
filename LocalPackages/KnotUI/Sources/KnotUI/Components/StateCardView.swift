import SwiftUI
import os.log
import KnotCore

private let log = Logger(subsystem: "KnotUI", category: "StateCard")

struct StateCardView: View {
    let status: TunnelStatus
    let certStatus: CertTrustStatus
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 14, height: 14)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }

            if certStatus != .trusted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(certWarningText)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                Button {
                    log.info("Start button tapped, isRunning=\(self.isRunning), status=\(self.statusText)")
                    onStart()
                } label: {
                    Label("启动", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                Button {
                    log.info("Stop button tapped")
                    onStop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isRunning)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            log.info("StateCardView appeared, status=\(self.statusText), isRunning=\(self.isRunning)")
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting, .reasserting: return .yellow
        default: return .red
        }
    }

    private var statusText: String {
        switch status {
        case .connected: return "已连接"
        case .connecting: return "连接中..."
        case .disconnecting: return "断开中..."
        case .reasserting: return "重连中..."
        case .disconnected: return "未连接"
        case .invalid: return "无效"
        case .error(let msg): return "错误: \(msg)"
        }
    }

    private var isRunning: Bool {
        if case .connected = status { return true }
        if case .connecting = status { return true }
        return false
    }

    private var certWarningText: String {
        switch certStatus {
        case .notInstalled: return "证书未安装，HTTPS 抓包不可用"
        case .installed: return "证书已安装，但尚未信任"
        case .trusted: return ""
        }
    }
}
