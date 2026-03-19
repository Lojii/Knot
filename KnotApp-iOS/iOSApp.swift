import SwiftUI
import TunnelServices
import KnotCore
import KnotUI

@main
struct KnotApp_iOS: App {

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
        let tunnelService = iOSTunnelService()
        let certService = iOSCertificateService()
        ServiceContainer.shared.register(TunnelServiceProtocol.self, instance: tunnelService)
        ServiceContainer.shared.register(CertificateServiceProtocol.self, instance: certService)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
