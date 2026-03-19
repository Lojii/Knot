import SwiftUI
import TunnelServices

struct DetailPageView: View {
    let destination: DetailDestination
    @Bindable var nav: NavigationState

    var body: some View {
        switch destination {
        case .flowList(let taskId):
            FlowListWrapper(taskId: taskId, nav: nav)
        case .flowDetail(let flowId, let taskId):
            FlowDetailWrapper(flowId: flowId, taskId: taskId)
        case .ruleDetail(let ruleId):
            RuleDetailView(ruleId: ruleId, nav: nav)
        case .ruleAdd(let ruleId):
            RuleAddView(ruleId: ruleId)
        case .settingCertificate:
            CertificateView()
        case .settingAbout:
            AboutView()
        case .settingWeb(let type):
            PlaceholderView()
                .navigationTitle(type.rawValue)
        }
    }
}

// MARK: - Wrappers

/// Resolves taskId -> TaskDatabaseGroup and presents FlowListView
private struct FlowListWrapper: View {
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

/// Resolves flowId + taskId -> FlowRecord + TaskDatabaseGroup and presents FlowDetailRouter
private struct FlowDetailWrapper: View {
    let flowId: String
    let taskId: String

    @State private var flow: FlowRecord?
    @State private var dbGroup: TaskDatabaseGroup?

    var body: some View {
        Group {
            if let flow, let dbGroup {
                FlowDetailRouter(flow: flow, dbGroup: dbGroup)
            } else {
                ProgressView()
            }
        }
        .onAppear { loadFlow() }
    }

    private func loadFlow() {
        guard let id = Int64(taskId) else { return }
        guard let group = try? DatabaseManager.shared.openTask(id) else { return }
        dbGroup = group
        flow = try? FlowDAO.find(db: group.proto, flowId: flowId)
    }
}
