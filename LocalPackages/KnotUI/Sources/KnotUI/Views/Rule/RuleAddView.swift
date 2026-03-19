import SwiftUI
import TunnelServices

struct RuleAddView: View {
    let ruleId: String

    @Environment(\.dismiss) private var dismiss

    @State private var matchType: MatchRule = .DOMAIN
    @State private var value: String = ""
    @State private var strategy: Strategy = .DIRECT
    @State private var note: String = ""

    private let matchTypes: [MatchRule] = [
        .DOMAIN, .DOMAINKEYWORD, .DOMAINSUFFIX, .IPCIDR, .USERAGENT, .URLREGEX
    ]

    private let strategies: [Strategy] = [.DIRECT, .REJECT, .COPY]

    var body: some View {
        Form {
            Section("匹配类型") {
                Picker("类型", selection: $matchType) {
                    ForEach(matchTypes, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
            }

            Section("匹配值") {
                TextField("例如: example.com", text: $value)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
            }

            Section("策略") {
                Picker("策略", selection: $strategy) {
                    ForEach(strategies, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
            }

            Section("备注") {
                TextField("可选备注", text: $note)
            }
        }
        .navigationTitle("添加规则")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveRule()
                    dismiss()
                }
                .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func saveRule() {
        guard let idNum = Int64(ruleId) else { return }
        let db = DatabaseManager.shared.catalogDB
        guard var record = try? CatalogDAO.findRule(db: db, id: idNum) else { return }

        var lineStr = "\(matchType.rawValue), \(value.trimmingCharacters(in: .whitespaces)), \(strategy.rawValue)"
        if !note.isEmpty {
            lineStr += " //\(note)"
        }

        // Append the new rule line to the [Rule] section of the config
        var config = record.config
        // Find [Rule] section or append one
        if let ruleRange = config.range(of: "[Rule]") {
            // Insert after [Rule] line
            let afterBracket = config[ruleRange.upperBound...]
            if let newline = afterBracket.firstIndex(of: "\n") {
                let insertIdx = config.index(after: newline)
                config.insert(contentsOf: lineStr + "\n", at: insertIdx)
            } else {
                config += "\n" + lineStr + "\n"
            }
        } else {
            config += "\n[Rule]\n" + lineStr + "\n"
        }

        record.config = config
        try? CatalogDAO.updateRule(db: db, record: record)
    }
}
