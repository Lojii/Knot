//
//  RetestFailedFlows.swift
//  TunnelServicesTests
//
//  Queries the most recent capture task for failed flows, then replays each
//  safe-to-retry request through a fresh proxy to see which failures are
//  transient vs. persistent.
//
//  Run with:
//      swift test --package-path LocalPackages/TunnelServices --filter RetestFailedFlows
//

import XCTest
import NIOCore
import NIOPosix
import NIOHTTP1
@testable import TunnelServices

final class RetestFailedFlows: XCTestCase {

    func testRetestAllFailedFlows() throws {
        // 1. Find most recent task
        let catalogDB = DatabaseManager.shared.catalogDB
        guard let task = CatalogDAO.findLastTask(db: catalogDB) else {
            print("[RETEST] No task found in catalog")
            return
        }
        print("[RETEST] Task ID: \(task.id)")

        // 2. Open task databases
        let group = try DatabaseManager.shared.openTask(task.id)
        defer { DatabaseManager.shared.closeTask(task.id) }

        // 3. Query all flows, filter failed
        let allFlows = try FlowDAO.query(db: group.proto, offset: 0, limit: 100_000)
        let failedFlows = allFlows.filter { $0.status == .failed }

        print("[RETEST] Total flows: \(allFlows.count), Failed: \(failedFlows.count)")
        guard !failedFlows.isEmpty else {
            print("[RETEST] No failed flows to retest")
            return
        }

        // 4. Start a fresh proxy to retest through
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()
        defer { launcher.stop() }

        var recovered = 0
        var stillFailing = 0
        var skipped = 0

        for (i, flow) in failedFlows.enumerated() {
            // Skip conditions
            if shouldSkip(flow) {
                skipped += 1
                print("[RETEST] [\(i+1)/\(failedFlows.count)] SKIP \(flow.host)\(flow.searchKey2) — \(skipReason(flow))")
                continue
            }

            let client = TestNIOClient(proxyPort: proxyPort)

            let method = HTTPMethod(rawValue: flow.searchKey1.isEmpty ? "GET" : flow.searchKey1)
            let uri = flow.searchKey2.isEmpty ? "/" : flow.searchKey2
            let port = flow.port > 0 ? flow.port : 443

            do {
                let rsp: TestHTTPResponse
                if flow.protocolName == "HTTPS" || flow.protocolName == "H2" {
                    rsp = try client.httpsRequest(
                        method: method,
                        host: flow.host, port: port, uri: uri
                    )
                } else {
                    rsp = try client.httpRequest(
                        method: method,
                        host: flow.host, port: port, uri: uri
                    )
                }

                let success = rsp.status >= 200 && rsp.status < 400
                if success { recovered += 1 } else { stillFailing += 1 }
                let errorPreview = String(flow.errorMessage.prefix(40))
                print("[RETEST] [\(i+1)/\(failedFlows.count)] \(success ? "PASS" : "FAIL") \(flow.host)\(uri) — was: \(errorPreview) -> now: \(rsp.status)")
            } catch {
                stillFailing += 1
                let errorPreview = String(flow.errorMessage.prefix(40))
                print("[RETEST] [\(i+1)/\(failedFlows.count)] FAIL \(flow.host)\(uri) — was: \(errorPreview) -> still: \(error)")
            }

            client.shutdown()
        }

        print("")
        print("[RETEST] === Summary ===")
        print("[RETEST] Total failed: \(failedFlows.count)")
        print("[RETEST] Skipped: \(skipped)")
        print("[RETEST] Retested: \(failedFlows.count - skipped)")
        print("[RETEST] Recovered: \(recovered)")
        print("[RETEST] Still failing: \(stillFailing)")
    }

    // MARK: - Skip Logic

    private func shouldSkip(_ flow: FlowRecord) -> Bool {
        let host = flow.host
        if host.isEmpty || host == "localhost" || host == "127.0.0.1" { return true }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("172.16.") { return true }
        let errLower = flow.errorMessage.lowercased()
        if errLower.contains("dns") || errLower.contains("resolve") { return true }
        if errLower.contains("certificate") || errLower.contains("cert") { return true }
        let method = flow.searchKey1.uppercased()
        if method == "POST" || method == "PUT" || method == "PATCH" || method == "DELETE" { return true }
        if flow.protocolName == "RAW" || flow.protocolName.isEmpty { return true }
        return false
    }

    private func skipReason(_ flow: FlowRecord) -> String {
        let host = flow.host
        if host.isEmpty || host == "localhost" || host == "127.0.0.1" { return "localhost" }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("172.16.") { return "private IP" }
        let errLower = flow.errorMessage.lowercased()
        if errLower.contains("dns") || errLower.contains("resolve") { return "DNS failure" }
        if errLower.contains("certificate") || errLower.contains("cert") { return "cert error" }
        let method = flow.searchKey1.uppercased()
        if ["POST", "PUT", "PATCH", "DELETE"].contains(method) { return "mutating method" }
        if flow.protocolName == "RAW" || flow.protocolName.isEmpty { return "unsupported protocol" }
        return "skip rule"
    }
}
