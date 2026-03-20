import SwiftUI
import os.log
import KnotCore
import TunnelServices

private let log = Logger(subsystem: "KnotUI", category: "Dashboard")

struct DashboardView: View {
    @Bindable var nav: NavigationState

    @State private var currentTask: CaptureTask?
    @State private var historyTasks: [CaptureTask] = []

    @State private var localEnabled = true
    @State private var localPort = "8034"
    @State private var wifiEnabled = false
    @State private var wifiPort = "8034"
    @State private var errorMessage: String?

    private var tunnelService: TunnelServiceProtocol? {
        ServiceContainer.shared.resolve(TunnelServiceProtocol.self)
    }

    /// Directly read from the @Observable TunnelServiceState so SwiftUI tracks changes.
    private var vpnStatus: TunnelStatus {
        tunnelService?.state.status ?? .disconnected
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StateCardView(
                    status: vpnStatus,
                    certStatus: .notInstalled,
                    onStart: startCapture,
                    onStop: stopCapture
                )
                .padding(.horizontal)

                ProxyConfigView(
                    localEnabled: $localEnabled,
                    localPort: $localPort,
                    wifiEnabled: $wifiEnabled,
                    wifiPort: $wifiPort,
                    wifiIP: nil
                )

                CurrentTaskView(task: currentTask) {
                    if let task = currentTask {
                        nav.navigate(to: .flowList(taskId: String(task.id)))
                    }
                }
                .padding(.horizontal)

                if !historyTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("最近任务")
                                .font(.headline)
                            Spacer()
                            Button("查看全部") {
                                nav.switchPrimary(to: .historyTask)
                            }
                            .font(.caption)
                        }
                        .padding(.horizontal)

                        ForEach(historyTasks, id: \.id) { task in
                            HistoryTaskCell(task: task) {
                                nav.navigate(to: .flowList(taskId: String(task.id)))
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("首页")
        .onAppear {
            loadHistoryTasks()
            loadCurrentTask()
        }
        .alert("启动失败", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startCapture() {
        log.info("startCapture: button tapped")
        log.info("startCapture: tunnelService=\(self.tunnelService != nil ? "resolved" : "nil")")
        guard let svc = tunnelService else {
            log.error("startCapture: tunnelService is nil!")
            errorMessage = "隧道服务未初始化"
            return
        }
        log.info("startCapture: vpnStatus=\(String(describing: self.vpnStatus))")
        let config = CaptureConfig(
            localPort: Int(localPort) ?? ProxyConfig.LocalProxy.port,
            localEnabled: localEnabled,
            wifiPort: Int(wifiPort) ?? ProxyConfig.WiFiProxy.defaultPort,
            wifiEnabled: wifiEnabled
        )
        log.info("startCapture: config local=\(config.localPort) wifi=\(config.wifiPort)")
        Task {
            do {
                log.info("startCapture: calling svc.startCapture...")
                try await svc.startCapture(config: config)
                log.info("startCapture: success")
                loadCurrentTask()
            } catch {
                log.error("startCapture: failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopCapture() {
        guard let svc = tunnelService else { return }
        Task {
            do {
                try await svc.stopCapture()
                loadCurrentTask()
                loadHistoryTasks()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadHistoryTasks() {
        historyTasks = Array(CaptureTask.findAll(pageSize: 5, pageIndex: 0, orderBy: "id").prefix(5))
    }

    private func loadCurrentTask() {
        currentTask = CaptureTask.getLast()
    }
}
