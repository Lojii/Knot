import SwiftUI
import TunnelServices

struct RuleDetailView: View {
    let ruleId: String
    @Bindable var nav: NavigationState

    @State private var selectedTab = 0
    @State private var rule: RuleRecord?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("概览").tag(0)
                Text("规则").tag(1)
                Text("Host").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            if let rule = rule {
                switch selectedTab {
                case 0:
                    ruleOverviewTab(rule)
                case 1:
                    ruleItemsTab(rule)
                default:
                    ruleHostTab(rule)
                }
            } else {
                ContentUnavailableView(
                    "加载中...",
                    systemImage: "hourglass"
                )
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("规则详情")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if selectedTab == 1 {
                    Button {
                        nav.navigate(to: .ruleAdd(ruleId: ruleId))
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear {
            loadRule()
        }
    }

    @ViewBuilder
    private func ruleOverviewTab(_ rule: RuleRecord) -> some View {
        List {
            Section("基本信息") {
                LabeledContent("名称", value: rule.name)
                LabeledContent("作者", value: rule.author.isEmpty ? "—" : rule.author)
                LabeledContent("创建时间", value: formattedDate(rule.createdAt))
            }

            Section("统计") {
                LabeledContent("规则数", value: "\(rule.ruleItems.count)")
                LabeledContent("Host 映射数", value: "\(rule.hosts.count)")
                LabeledContent("默认策略", value: rule.defaultStrategy)
            }

            if !rule.note.isEmpty {
                Section("备注") {
                    Text(rule.note)
                        .font(.body)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    private func ruleItemsTab(_ rule: RuleRecord) -> some View {
        if rule.ruleItems.isEmpty {
            ContentUnavailableView(
                "暂无规则项",
                systemImage: "list.bullet",
                description: Text("点击右上角添加规则")
            )
        } else {
            List {
                ForEach(Array(rule.ruleItems.enumerated()), id: \.offset) { _, item in
                    RuleMatchRow(item: item)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func ruleHostTab(_ rule: RuleRecord) -> some View {
        if rule.hosts.isEmpty {
            ContentUnavailableView(
                "暂无 Host 映射",
                systemImage: "network",
                description: Text("该规则没有 Host 映射配置")
            )
        } else {
            List {
                ForEach(Array(rule.hosts.enumerated()), id: \.offset) { _, host in
                    Text(host.line)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .listStyle(.plain)
        }
    }

    private func loadRule() {
        guard let idNum = Int64(ruleId) else { return }
        rule = try? CatalogDAO.findRule(db: DatabaseManager.shared.catalogDB, id: idNum)
    }

    private func formattedDate(_ ts: TimeInterval) -> String {
        guard ts > 0 else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: ts))
    }
}
