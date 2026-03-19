import SwiftUI
import os.log
import TunnelServices
import KnotCore
import KnotUI

private let log = Logger(subsystem: "com.KingMap.KnotApp-macOS", category: "AppInit")

@main
struct KnotApp_macOS: App {

    init() {
        log.info("KnotApp_macOS init start")

        // Initialize storage layer (creates catalog.db and tables automatically)
        _ = DatabaseManager.shared
        log.info("DatabaseManager initialized")

        // First launch: ensure a default rule exists
        let catalogDB = DatabaseManager.shared.catalogDB
        if let rules = try? CatalogDAO.findAllRules(db: catalogDB), rules.isEmpty {
            _ = try? CatalogDAO.insertRule(
                db: catalogDB, name: "Knot(Default)", config: "",
                createdAt: Date().timeIntervalSince1970,
                defaultStrategy: "DIRECT", blacklistEnabled: true, author: "Knot")
            log.info("Default rule created")
        }

        // Register services into ServiceContainer
        let tunnelService = macOSTunnelService()
        let certService = macOSCertificateService()
        ServiceContainer.shared.register(TunnelServiceProtocol.self, instance: tunnelService)
        ServiceContainer.shared.register(CertificateServiceProtocol.self, instance: certService)
        log.info("Services registered: tunnelService=\(type(of: tunnelService)), certService=\(type(of: certService))")
        log.info("KnotApp_macOS init done")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1100, height: 700)
    }
}
