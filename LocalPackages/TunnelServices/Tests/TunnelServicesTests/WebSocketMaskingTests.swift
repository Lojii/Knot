import XCTest
import NIOWebSocket
import NIO
@testable import TunnelServices

final class WebSocketMaskingTests: XCTestCase {
    func testRandomMaskingKeyGeneration() {
        let key = WebSocketMaskingKey([
            UInt8.random(in: 0...255), UInt8.random(in: 0...255),
            UInt8.random(in: 0...255), UInt8.random(in: 0...255)
        ])
        XCTAssertNotNil(key)
    }

    func testMaskedFrameHasMaskKey() {
        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 5)
        buf.writeString("hello")
        let key = WebSocketMaskingKey([1, 2, 3, 4])!
        let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: key, data: buf)
        XCTAssertNotNil(frame.maskKey)
    }

    func testUnmaskedFrameHasNoMaskKey() {
        let allocator = ByteBufferAllocator()
        var buf = allocator.buffer(capacity: 5)
        buf.writeString("hello")
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
        XCTAssertNil(frame.maskKey)
    }
}
