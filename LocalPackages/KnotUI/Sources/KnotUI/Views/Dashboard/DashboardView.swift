import SwiftUI
import KnotCore
import TunnelServices

struct DashboardView: View {
    @Bindable var nav: NavigationState

    @State private var appState = AppState()
    @State private var historyTasks: [CaptureTask] = []

    @State private var localEnabled = true
    @State private var localPort = "9090"
    @State private var wifiEnabled = false
    @State private var wifiPort = "9091"

    private var tunnelService: TunnelServiceProtocol? {
        ServiceContainer.shared.resolve(TunnelServiceProtocol.self)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StateCardView(
                    status: appState.vpnStatus,
                    certStatus: appState.certificateStatus,
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

                CurrentTaskView(task: appState.currentTask) {
                    if let task = appState.currentTask, let taskId = task.id {
                        nav.navigate(to: .flowList(taskId: taskId.stringValue))
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
                                if let taskId = task.id {
                                    nav.navigate(to: .flowList(taskId: taskId.stringValue))
                                }
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
    }

    private func startCapture() {
        guard let svc = tunnelService else { return }
        let config = CaptureConfig(
            localPort: Int(localPort) ?? 9090,
            localEnabled: localEnabled,
            wifiPort: Int(wifiPort) ?? 9091,
            wifiEnabled: wifiEnabled,
            ruleId: appState.activeRuleId
        )
        Task {
            try? await svc.startCapture(config: config)
        }
    }

    private func stopCapture() {
        guard let svc = tunnelService else { return }
        Task {
            try? await svc.stopCapture()
        }
    }

    private func loadHistoryTasks() {
        historyTasks = Array(CaptureTask.findAll(pageSize: 5, pageIndex: 0, orderBy: "id").prefix(5))
    }

    private func loadCurrentTask() {
        appState.currentTask = CaptureTask.getLast()
    }
}
