import SwiftUI
import TunnelServices

/// Unified flow list view replacing SessionListView
public struct FlowListView: View {
    @StateObject private var vm: FlowListViewModel
    @State private var searchText = ""
    @State private var protocolFilter: String?

    private let nav: NavigationState
    private let taskId: String

    public init(dbGroup: TaskDatabaseGroup, nav: NavigationState, taskId: String) {
        _vm = StateObject(wrappedValue: FlowListViewModel(dbGroup: dbGroup))
        self.nav = nav
        self.taskId = taskId
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Protocol filter bar
            ProtocolFilterBar(selected: $protocolFilter, counts: vm.protocolCounts)

            // Flow list
            List {
                ForEach(vm.flows, id: \.flowId) { flow in
                    Button {
                        nav.navigate(to: .flowDetail(flowId: flow.flowId, taskId: taskId))
                    } label: {
                        FlowCell(flow: flow)
                    }
                }

                // Load more trigger
                if vm.hasMore {
                    ProgressView()
                        .onAppear { vm.loadMore() }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, prompt: "搜索 Host / URI / 内容")
        .onChange(of: searchText) { _, newValue in
            vm.keyword = newValue.isEmpty ? nil : newValue
            vm.loadFlows()
        }
        .onChange(of: protocolFilter) { _, newValue in
            vm.protocolFilter = newValue
            vm.loadFlows()
        }
        .onAppear {
            vm.loadFlows()
        }
        .refreshable {
            vm.refresh()
        }
    }
}
