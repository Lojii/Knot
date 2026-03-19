import SwiftUI
import TunnelServices

struct PrimaryPageView: View {
    @Bindable var nav: NavigationState

    var body: some View {
        VStack(spacing: 0) {
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            PageSwitcher(nav: nav)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch nav.primaryPage {
        case .dashboard:
            DashboardView(nav: nav)
        case .flowList(let taskId):
            PrimaryFlowListWrapper(taskId: taskId, nav: nav)
        case .ruleList:
            RuleListView(nav: nav)
        case .certificate:
            CertificateView()
        case .historyTask:
            HistoryTaskView(nav: nav)
        case .settings:
            SettingsView(nav: nav)
        }
    }
}

/// Resolves taskId -> TaskDatabaseGroup for the primary page FlowListView
private struct PrimaryFlowListWrapper: View {
    let taskId: String
    @Bindable var nav: NavigationState

    @State private var dbGroup: TaskDatabaseGroup?

    var body: some View {
        Group {
            if let dbGroup {
                FlowListView(dbGroup: dbGroup, nav: nav, taskId: taskId)
            } else {
                ProgressView()
            }
        }
        .onAppear { openDatabase() }
    }

    private func openDatabase() {
        guard let id = Int64(taskId) else { return }
        dbGroup = try? DatabaseManager.shared.openTask(id)
    }
}
