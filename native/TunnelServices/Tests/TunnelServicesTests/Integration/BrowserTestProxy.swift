import XCTest
import Foundation
@testable import TunnelServices

/// Long-running test that starts the proxy for browser testing.
/// Run: swift test --package-path LocalPackages/TunnelServices --filter testStartProxyForBrowserTest
///
/// The proxy stays alive until the test times out or is killed (Ctrl+C).
/// Use with: node Scripts/browser-test/browser-test.js --auto --proxy-port <PORT>
final class BrowserTestProxy: XCTestCase {

    func testStartProxyForBrowserTest() throws {
        let launcher = try TestProxyLauncher(sslEnabled: true, withCA: true)
        let proxyPort = try launcher.start()

        print("")
        print("==============================================")
        print("  PROXY READY")
        print("  Proxy:     127.0.0.1:\(proxyPort)")
        print("  Dashboard: http://127.0.0.1:9090")
        print("")
        print("  Run in another terminal:")
        print("  node Scripts/browser-test/browser-test.js --auto --proxy-port \(proxyPort)")
        print("")
        print("  Or open dashboard: http://127.0.0.1:9090")
        print("  Press Ctrl+C to stop")
        print("==============================================")
        print("")

        // Write port to temp file so Puppeteer can read it
        let portFile = "/tmp/knot-proxy-port"
        try "\(proxyPort)".write(toFile: portFile, atomically: true, encoding: .utf8)

        // Keep alive for 30 minutes (or until killed)
        Thread.sleep(forTimeInterval: 1800)

        launcher.stop()
    }
}
