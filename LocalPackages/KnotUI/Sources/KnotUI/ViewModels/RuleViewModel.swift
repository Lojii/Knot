import Foundation
import Observation
import TunnelServices

private let kActiveRuleIdKey = "activeRuleId"
private let kAppGroupSuite = "group.Lojii.NIO1901"

@Observable
public final class RuleViewModel {
    public var rules: [RuleRecord] = []
    public var activeRuleId: String?

    private let defaults = UserDefaults(suiteName: kAppGroupSuite)

    public init() {
        activeRuleId = defaults?.string(forKey: kActiveRuleIdKey)
    }

    public func loadRules() {
        rules = (try? CatalogDAO.findAllRules(db: DatabaseManager.shared.catalogDB)) ?? []
        if activeRuleId == nil, let first = rules.first {
            activeRuleId = String(first.id)
        }
    }

    public func setActive(ruleId: String) {
        activeRuleId = ruleId
        defaults?.set(ruleId, forKey: kActiveRuleIdKey)
        defaults?.synchronize()
    }

    public func deleteRule(_ rule: RuleRecord) {
        try? CatalogDAO.deleteRule(db: DatabaseManager.shared.catalogDB, id: rule.id)
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules.remove(at: idx)
        }
        if String(rule.id) == activeRuleId {
            activeRuleId = nil
            defaults?.removeObject(forKey: kActiveRuleIdKey)
        }
    }

    public func createDefaultRule() {
        let config = """
            [General]
            name = Knot(Default)
            default-strategy = DIRECT
            default-direct-enable = true
            createtime = \(Date().fullSting)
            author = Knot
            [Rule]
            [Host]
            """
        _ = try? CatalogDAO.insertRule(
            db: DatabaseManager.shared.catalogDB,
            name: "Knot(Default)",
            config: config,
            createdAt: Date().timeIntervalSince1970,
            defaultStrategy: "DIRECT",
            blacklistEnabled: true,
            author: "Knot"
        )
        loadRules()
    }
}
