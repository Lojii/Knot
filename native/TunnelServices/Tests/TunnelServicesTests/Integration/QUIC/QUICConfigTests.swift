import XCTest
@testable import TunnelServices

final class QUICConfigTests: XCTestCase {

    func testDefaultConfig() throws {
        XCTAssertFalse(ProxyConfig.HTTP3.enabled)
        XCTAssertEqual(ProxyConfig.HTTP3.backend, .quiche)
        XCTAssertEqual(ProxyConfig.HTTP3.maxSessions, 20)
        XCTAssertEqual(ProxyConfig.HTTP3.idleTimeoutMs, 30_000)
    }

    func testBackendEnum() throws {
        XCTAssertEqual(ProxyConfig.HTTP3.Backend.quiche.rawValue, "quiche")
        XCTAssertEqual(ProxyConfig.HTTP3.Backend.lsquic.rawValue, "lsquic")
    }
}
