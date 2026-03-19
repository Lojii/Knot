import SwiftUI
import TunnelServices
import KnotCore
import KnotUI

@main
struct KnotApp_macOS: App {

    init() {
        // Initialize new storage layer (creates catalog.db and tables automatically)
        _ = DatabaseManager.shared

        // Legacy database setup (for Rule and other ActiveSQLite models still in use)
        ASConfigration.setDefaultDB(path: MitmService.getDBPath(), name: ProxyConfig.Database.sessionTableName)
        try? CaptureTask.createTable()
        try? Rule.createTable()

        // First launch: save default rule if none exist
        if Rule.findRules().isEmpty {
            let defaultRule = Rule.defaultRule()
            try? defaultRule.saveToDB()
        }

        // Register services into ServiceContainer
        let tunnelService = macOSTunnelService()
        let certService = macOSCertificateService()
        ServiceContainer.shared.register(TunnelServiceProtocol.self, instance: tunnelService)
        ServiceContainer.shared.register(CertificateServiceProtocol.self, instance: certService)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 700)
    }
}
