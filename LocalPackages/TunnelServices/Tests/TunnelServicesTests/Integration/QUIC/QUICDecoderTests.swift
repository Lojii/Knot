import XCTest
@testable import TunnelServices

final class QUICDecoderTests: XCTestCase {

    // MARK: - Helper: build a QUIC long header

    /// Build a minimal QUIC long header.
    /// Format: flags(1) + version(4) + dcidLen(1) + dcid(N) + scidLen(1) + scid(M) + trailing payload
    private func makeLongHeader(
        typeBits: UInt8,      // 2-bit type in bits 4-5 of first byte
        version: UInt32,
        dcid: [UInt8],
        scid: [UInt8],
        payload: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    ) -> Data {
        // First byte: header form bit (0x80) | fixed bit (0x40) | typeBits << 4
        let firstByte: UInt8 = 0xC0 | (typeBits << 4)
        var bytes: [UInt8] = [firstByte]
        // Version (big-endian)
        bytes.append(UInt8((version >> 24) & 0xFF))
        bytes.append(UInt8((version >> 16) & 0xFF))
        bytes.append(UInt8((version >> 8) & 0xFF))
        bytes.append(UInt8(version & 0xFF))
        // DCID
        bytes.append(UInt8(dcid.count))
        bytes.append(contentsOf: dcid)
        // SCID
        bytes.append(UInt8(scid.count))
        bytes.append(contentsOf: scid)
        // Trailing payload bytes
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    // MARK: - Long Header Tests

    func testParseLongHeader_Initial() throws {
        let dcid: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        let scid: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD]
        let data = makeLongHeader(typeBits: 0, version: 0x00000001, dcid: dcid, scid: scid)

        let header = QUICDecoder.parseHeader(data)
        XCTAssertNotNil(header)
        XCTAssertTrue(header!.isLongHeader)
        XCTAssertEqual(header!.packetType, .initial)
        XCTAssertEqual(header!.version, 0x00000001)
        XCTAssertEqual(header!.dcidLength, 8)
        XCTAssertEqual(header!.dcid, Data(dcid))
        XCTAssertEqual(header!.scidLength, 4)
        XCTAssertEqual(header!.scid, Data(scid))
    }

    func testParseLongHeader_Handshake() throws {
        let dcid: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let scid: [UInt8] = [0x05, 0x06, 0x07, 0x08]
        // typeBits=2 => Handshake
        let data = makeLongHeader(typeBits: 2, version: 0x00000001, dcid: dcid, scid: scid)

        let header = QUICDecoder.parseHeader(data)
        XCTAssertNotNil(header)
        XCTAssertTrue(header!.isLongHeader)
        XCTAssertEqual(header!.packetType, .handshake)
    }

    func testParseShortHeader() throws {
        // Short header: first bit = 0 => 0x40 (fixed bit set, header form bit clear)
        var bytes: [UInt8] = [0x40]
        // Add enough bytes for DCID (heuristic assumes 8 bytes) + some payload
        bytes.append(contentsOf: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0xFF, 0xFF])
        let data = Data(bytes)

        let header = QUICDecoder.parseHeader(data)
        XCTAssertNotNil(header)
        XCTAssertFalse(header!.isLongHeader)
        XCTAssertEqual(header!.packetType, .shortHeader)
        XCTAssertNil(header!.version)
        XCTAssertNil(header!.scid)
    }

    func testParseVersionNegotiation() throws {
        let dcid: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let scid: [UInt8] = [0x05, 0x06]
        // Version = 0 => Version Negotiation => packetType = .unknown
        let data = makeLongHeader(typeBits: 0, version: 0, dcid: dcid, scid: scid)

        let header = QUICDecoder.parseHeader(data)
        XCTAssertNotNil(header)
        XCTAssertEqual(header!.packetType, .unknown)
        XCTAssertEqual(header!.version, 0)
    }

    func testParseTooShort() throws {
        let data = Data([0xC0, 0x00])  // Only 2 bytes, not enough for long header (need >= 7)
        let header = QUICDecoder.parseHeader(data)
        XCTAssertNil(header)
    }

    // MARK: - isQUIC

    func testIsQUIC_ValidInitial() throws {
        let data = makeLongHeader(typeBits: 0, version: 0x00000001,
                                  dcid: [0x01, 0x02, 0x03, 0x04],
                                  scid: [0x05, 0x06])
        XCTAssertTrue(QUICDecoder.isQUIC(data))
    }

    func testIsQUIC_HTTPRequest() throws {
        let data = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".data(using: .utf8)!
        XCTAssertFalse(QUICDecoder.isQUIC(data))
    }

    func testIsQUIC_TLSClientHello() throws {
        // TLS record header: content_type=0x16, version=0x0301, length
        let data = Data([0x16, 0x03, 0x01, 0x00, 0x05, 0x01, 0x00, 0x00, 0x01, 0x00])
        XCTAssertFalse(QUICDecoder.isQUIC(data))
    }

    func testIsQUIC_Empty() throws {
        XCTAssertFalse(QUICDecoder.isQUIC(Data()))
    }

    // MARK: - extractSNI

    func testExtractSNI_NotInitial() throws {
        // Handshake packet (typeBits=2) => not Initial => extractSNI returns nil
        let data = makeLongHeader(typeBits: 2, version: 0x00000001,
                                  dcid: [0x01, 0x02, 0x03, 0x04],
                                  scid: [0x05, 0x06])
        let sni = QUICDecoder.extractSNI(data)
        XCTAssertNil(sni)
    }

    // MARK: - format

    func testFormat_Initial() throws {
        let dcid: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        let scid: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD]
        let data = makeLongHeader(typeBits: 0, version: 0x00000001, dcid: dcid, scid: scid)

        let header = QUICDecoder.parseHeader(data)!
        let formatted = QUICDecoder.format(header)
        XCTAssertTrue(formatted.contains("Initial"), "format should contain 'Initial', got: \(formatted)")
        XCTAssertTrue(formatted.contains("QUIC"), "format should contain 'QUIC', got: \(formatted)")
    }
}
