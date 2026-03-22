import XCTest
@testable import TunnelServices

final class ProtoFlagTests: XCTestCase {
    func testSingleFlag() {
        var flags = ProtoFlag()
        flags.insert(.keepAlive)
        XCTAssertEqual(flags.rawValue, 0x0001)
        XCTAssertTrue(flags.contains(.keepAlive))
        XCTAssertFalse(flags.contains(.h2Multiplexing))
    }

    func testMultipleFlags() {
        var flags: ProtoFlag = [.keepAlive, .tlsMITM, .tlsHandshakeOK]
        XCTAssertEqual(flags.rawValue, 0x0001 | 0x0040 | 0x0100)
        XCTAssertTrue(flags.contains(.keepAlive))
        XCTAssertTrue(flags.contains(.tlsMITM))
        XCTAssertTrue(flags.contains(.tlsHandshakeOK))
        XCTAssertFalse(flags.contains(.pipelining))
    }

    func testBitmaskRoundTrip() {
        let value = 0x0001 | 0x0004 | 0x0020
        let flags = ProtoFlag(rawValue: value)
        XCTAssertTrue(flags.contains(.keepAlive))
        XCTAssertTrue(flags.contains(.h2Multiplexing))
        XCTAssertTrue(flags.contains(.wsFrameMasked))
        XCTAssertEqual(flags.rawValue, value)
    }

    func testConnectionReuseType() {
        XCTAssertEqual(ConnectionReuseType.new.rawValue, 0)
        XCTAssertEqual(ConnectionReuseType.keepAlive.rawValue, 1)
        XCTAssertEqual(ConnectionReuseType.pooled.rawValue, 2)
    }

    func testPushForwardStatus() {
        XCTAssertEqual(PushForwardStatus.captureOnly.rawValue, 0)
        XCTAssertEqual(PushForwardStatus.forwarded.rawValue, 1)
        XCTAssertEqual(PushForwardStatus.failed.rawValue, 2)
    }
}
