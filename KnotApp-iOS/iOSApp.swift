import SwiftUI
import TunnelServices
import KnotCore
import KnotUI

@main
struct KnotApp_iOS: App {

    init() {
        // Initialize storage layer (creates catalog.db and tables automatically)
        _ = DatabaseManager.shared

        // First launch: ensure a default rule exists
        let catalogDB = DatabaseManager.shared.catalogDB
        if let rules = try? CatalogDAO.findAllRules(db: catalogDB), rules.isEmpty {
            _ = try? CatalogDAO.insertRule(
                db: catalogDB, name: "Knot(Default)", config: "",
                createdAt: Date().timeIntervalSince1970,
                defaultStrategy: "DIRECT", blacklistEnabled: true, author: "Knot")
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
