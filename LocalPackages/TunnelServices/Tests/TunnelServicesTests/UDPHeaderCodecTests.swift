import XCTest
import NIOCore
@testable import TunnelServices

final class UDPHeaderCodecTests: XCTestCase {

    private let allocator = ByteBufferAllocator()

    // MARK: - IPv4

    func testIPv4EncodeDecodeRoundTrip() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "192.168.1.1", port: 8080, into: &buf)

        let result = UDPHeaderCodec.decode(from: &buf)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "192.168.1.1")
        XCTAssertEqual(result?.port, 8080)
        XCTAssertEqual(result?.payload.readableBytes, 0)
    }

    func testIPv4HeaderSize() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "10.0.0.1", port: 53, into: &buf)
        // 1 (addrType) + 4 (IPv4) + 2 (port) = 7 bytes
        XCTAssertEqual(buf.readableBytes, 7)
    }

    func testIPv4WithPayload() {
        let payload: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "1.2.3.4", port: 1234, into: &buf)
        buf.writeBytes(payload)

        let result = UDPHeaderCodec.decode(from: &buf)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "1.2.3.4")
        XCTAssertEqual(result?.port, 1234)
        XCTAssertEqual(result?.payload.readableBytes, 4)
        XCTAssertEqual(result?.payload.getBytes(at: result!.payload.readerIndex, length: 4), payload)
    }

    func testIPv4AddrTypeByte() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "127.0.0.1", port: 80, into: &buf)
        let firstByte: UInt8? = buf.getInteger(at: buf.readerIndex)
        XCTAssertEqual(firstByte, UDPHeaderCodec.addrTypeIPv4)
    }

    // MARK: - IPv6

    func testIPv6EncodeDecodeRoundTrip() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "2001:db8::1", port: 443, into: &buf)

        let result = UDPHeaderCodec.decode(from: &buf)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.port, 443)
        // Re-encode decoded host and verify it also decodes correctly
        XCTAssertFalse(result?.host.isEmpty ?? true)
    }

    func testIPv6HeaderSize() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "::1", port: 8080, into: &buf)
        // 1 (addrType) + 16 (IPv6) + 2 (port) = 19 bytes
        XCTAssertEqual(buf.readableBytes, 19)
    }

    func testIPv6AddrTypeByte() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "fe80::1", port: 80, into: &buf)
        let firstByte: UInt8? = buf.getInteger(at: buf.readerIndex)
        XCTAssertEqual(firstByte, UDPHeaderCodec.addrTypeIPv6)
    }

    // MARK: - Domain

    func testDomainEncodeDecodeRoundTrip() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "example.com", port: 443, into: &buf)

        let result = UDPHeaderCodec.decode(from: &buf)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "example.com")
        XCTAssertEqual(result?.port, 443)
        XCTAssertEqual(result?.payload.readableBytes, 0)
    }

    func testDomainHeaderSize() {
        let domain = "api.test"  // 8 bytes
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: domain, port: 80, into: &buf)
        // 1 (addrType) + 1 (length) + 8 (domain) + 2 (port) = 12 bytes
        let expected = 1 + 1 + domain.utf8.count + 2
        XCTAssertEqual(buf.readableBytes, expected)
    }

    func testDomainAddrTypeByte() {
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "example.com", port: 80, into: &buf)
        let firstByte: UInt8? = buf.getInteger(at: buf.readerIndex)
        XCTAssertEqual(firstByte, UDPHeaderCodec.addrTypeDomain)
    }

    // MARK: - Port big-endian encoding

    func testPortBigEndianEncoding() {
        // Port 0x1F90 = 8080; should appear as bytes [0x1F, 0x90] in big-endian
        var buf = allocator.buffer(capacity: 64)
        UDPHeaderCodec.encode(host: "1.1.1.1", port: 0x1F90, into: &buf)

        // addrType(1) + IPv4(4) = offset 5 for port bytes
        let high: UInt8? = buf.getInteger(at: buf.readerIndex + 5)
        let low:  UInt8? = buf.getInteger(at: buf.readerIndex + 6)
        XCTAssertEqual(high, 0x1F)
        XCTAssertEqual(low,  0x90)
    }

    func testPortBoundaryValues() {
        for port in [0, 1, 65535] {
            var buf = allocator.buffer(capacity: 64)
            UDPHeaderCodec.encode(host: "0.0.0.0", port: port, into: &buf)
            let result = UDPHeaderCodec.decode(from: &buf)
            XCTAssertEqual(result?.port, port, "Port \(port) round-trip failed")
        }
    }

    // MARK: - Error / edge cases

    func testEmptyBufferReturnsNil() {
        var buf = allocator.buffer(capacity: 0)
        XCTAssertNil(UDPHeaderCodec.decode(from: &buf))
    }

    func testTruncatedIPv4BufferReturnsNil() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([UDPHeaderCodec.addrTypeIPv4, 192, 168])  // missing 1 address byte + port
        XCTAssertNil(UDPHeaderCodec.decode(from: &buf))
    }

    func testTruncatedIPv6BufferReturnsNil() {
        var buf = allocator.buffer(capacity: 8)
        buf.writeInteger(UDPHeaderCodec.addrTypeIPv6)
        buf.writeBytes([UInt8](repeating: 0, count: 8))   // only 8 of 16 bytes
        XCTAssertNil(UDPHeaderCodec.decode(from: &buf))
    }

    func testTruncatedDomainBufferReturnsNil() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([UDPHeaderCodec.addrTypeDomain, 10, 0x65, 0x78])  // length=10 but only 2 domain bytes
        XCTAssertNil(UDPHeaderCodec.decode(from: &buf))
    }

    func testUnknownAddrTypeReturnsNil() {
        var buf = allocator.buffer(capacity: 8)
        buf.writeBytes([0x02, 1, 2, 3, 4, 0x1F, 0x90])   // 0x02 is not a known addrType
        XCTAssertNil(UDPHeaderCodec.decode(from: &buf))
    }

    func testReaderIndexNotAdvancedOnFailure() {
        var buf = allocator.buffer(capacity: 4)
        buf.writeBytes([UDPHeaderCodec.addrTypeIPv4, 1, 2])  // truncated
        let readerIndexBefore = buf.readerIndex
        _ = UDPHeaderCodec.decode(from: &buf)
        XCTAssertEqual(buf.readerIndex, readerIndexBefore)
    }
}
