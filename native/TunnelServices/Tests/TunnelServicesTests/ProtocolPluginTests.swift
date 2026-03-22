import XCTest
import NIO
@testable import TunnelServices

final class ProtocolPluginTests: XCTestCase {

    // MARK: - MatchResult equality

    func testMatchResultYesEquality() {
        XCTAssertEqual(MatchResult.yes(confidence: 80), MatchResult.yes(confidence: 80))
        XCTAssertNotEqual(MatchResult.yes(confidence: 80), MatchResult.yes(confidence: 50))
    }

    func testMatchResultNoEquality() {
        XCTAssertEqual(MatchResult.no, MatchResult.no)
        XCTAssertNotEqual(MatchResult.no, MatchResult.yes(confidence: 100))
    }

    func testMatchResultNeedMoreDataEquality() {
        XCTAssertEqual(MatchResult.needMoreData(minimum: 4), MatchResult.needMoreData(minimum: 4))
        XCTAssertNotEqual(MatchResult.needMoreData(minimum: 4), MatchResult.needMoreData(minimum: 8))
    }

    func testMatchResultCrossVariantInequality() {
        XCTAssertNotEqual(MatchResult.yes(confidence: 100), MatchResult.needMoreData(minimum: 1))
        XCTAssertNotEqual(MatchResult.no, MatchResult.needMoreData(minimum: 0))
    }

    // MARK: - ProtocolMetadata defaults

    func testProtocolMetadataEmptyDefaults() {
        let meta = ProtocolMetadata.empty
        XCTAssertNil(meta.parentId)
        XCTAssertNil(meta.alpnResult)
        XCTAssertNil(meta.sni)
        XCTAssertNil(meta.innerHost)
        XCTAssertNil(meta.innerPort)
        XCTAssertFalse(meta.isEncrypted)
        XCTAssertTrue(meta.extra.isEmpty)
    }

    func testProtocolMetadataDefaultInitMatchesEmpty() {
        let meta = ProtocolMetadata()
        XCTAssertNil(meta.parentId)
        XCTAssertNil(meta.alpnResult)
        XCTAssertNil(meta.sni)
        XCTAssertNil(meta.innerHost)
        XCTAssertNil(meta.innerPort)
        XCTAssertFalse(meta.isEncrypted)
        XCTAssertTrue(meta.extra.isEmpty)
    }

    func testProtocolMetadataMutation() {
        var meta = ProtocolMetadata()
        meta.sni = "example.com"
        meta.isEncrypted = true
        meta.innerPort = 443
        meta.extra["key"] = "value"

        XCTAssertEqual(meta.sni, "example.com")
        XCTAssertTrue(meta.isEncrypted)
        XCTAssertEqual(meta.innerPort, 443)
        XCTAssertEqual(meta.extra["key"] as? String, "value")
    }

    // MARK: - MatchContext initialization

    func testMatchContextDefaultInit() {
        let ctx = MatchContext(localPort: 8080)
        XCTAssertEqual(ctx.localPort, 8080)
        XCTAssertNil(ctx.remoteAddress)
        XCTAssertNil(ctx.parentProtocol)
    }

    func testMatchContextFullInit() {
        let meta = ProtocolMetadata()
        let ctx = MatchContext(
            localPort: 443,
            remoteAddress: nil,
            parentProtocol: "tls",
            metadata: meta
        )
        XCTAssertEqual(ctx.localPort, 443)
        XCTAssertEqual(ctx.parentProtocol, "tls")
        XCTAssertNil(ctx.remoteAddress)
    }
}
