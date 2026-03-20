import XCTest
import NIO
@testable import TunnelServices

// MARK: - StubPlugin

/// A minimal ProtocolPlugin used for deterministic testing.
/// Matches buffers whose readable bytes start with `prefix`; returns
/// `.needMoreData(minimum:)` when the buffer is shorter than the prefix.
private final class StubPlugin: ProtocolPlugin {
    let id: String
    let displayName: String
    let prefix: [UInt8]
    let matchConfidence: Int

    init(id: String, prefix: String, confidence: Int) {
        self.id               = id
        self.displayName      = id
        self.prefix           = Array(prefix.utf8)
        self.matchConfidence  = confidence
    }

    func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        let needed = prefix.count
        guard buffer.readableBytes >= needed else {
            return .needMoreData(minimum: needed)
        }
        let head = buffer.getBytes(at: buffer.readerIndex, length: needed) ?? []
        return head == prefix ? .yes(confidence: matchConfidence) : .no
    }

    func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        return context.channel.eventLoop.makeSucceededVoidFuture()
    }

    func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        return nil
    }
}

// MARK: - ProtocolDispatcherTests

final class ProtocolDispatcherTests: XCTestCase {

    private var allocator = ByteBufferAllocator()
    private let matchCtx  = MatchContext(localPort: 8080)

    // MARK: - Helpers

    private func makeBuffer(_ string: String) -> ByteBuffer {
        var buf = allocator.buffer(capacity: string.utf8.count)
        buf.writeString(string)
        return buf
    }

    private func nodes(_ plugins: [StubPlugin]) -> [ProtocolNode] {
        return plugins.map { ProtocolNode(plugin: $0) }
    }

    // MARK: - testHighestConfidenceWins

    /// When two plugins both match, the one with higher confidence is chosen.
    func testHighestConfidenceWins() {
        let low  = StubPlugin(id: "low",  prefix: "GET", confidence: 40)
        let high = StubPlugin(id: "high", prefix: "GET", confidence: 90)

        let buf = makeBuffer("GET / HTTP/1.1\r\n")
        let outcome = ProtocolDispatcher.selectWinner(
            from: nodes([low, high]),
            buffer: buf,
            context: matchCtx
        )

        if case .matched(let node) = outcome {
            XCTAssertEqual(node.plugin.id, "high",
                "Expected highest-confidence plugin to win")
        } else {
            XCTFail("Expected a match, got \(outcome)")
        }
    }

    // MARK: - testArrayOrderBreaksTie

    /// When two plugins share the same confidence, the one appearing first in
    /// the array wins (stable ordering).
    func testArrayOrderBreaksTie() {
        let first  = StubPlugin(id: "first",  prefix: "GET", confidence: 70)
        let second = StubPlugin(id: "second", prefix: "GET", confidence: 70)

        let buf = makeBuffer("GET / HTTP/1.1\r\n")
        let outcome = ProtocolDispatcher.selectWinner(
            from: nodes([first, second]),
            buffer: buf,
            context: matchCtx
        )

        if case .matched(let node) = outcome {
            XCTAssertEqual(node.plugin.id, "first",
                "Array order should break ties — first plugin should win")
        } else {
            XCTFail("Expected a match, got \(outcome)")
        }
    }

    // MARK: - testNeedMoreDataWithInsufficientBytes

    /// When the buffer is shorter than the plugin's required prefix, the
    /// outcome should be `.needMoreData`, not `.noMatch`.
    func testNeedMoreDataWithInsufficientBytes() {
        // Requires 4 bytes ("HTTP"), but we only give 2.
        let plugin = StubPlugin(id: "http", prefix: "HTTP", confidence: 80)

        var buf = allocator.buffer(capacity: 2)
        buf.writeBytes([0x48, 0x54])   // "HT"

        let outcome = ProtocolDispatcher.selectWinner(
            from: nodes([plugin]),
            buffer: buf,
            context: matchCtx
        )

        if case .needMoreData = outcome {
            // Correct
        } else {
            XCTFail("Expected .needMoreData, got \(outcome)")
        }
    }

    // MARK: - testNoMatchReturnsNoMatch

    /// When no plugin matches AND none needs more data, the outcome should be
    /// `.noMatch` (triggering a Raw fallback in the dispatcher).
    func testNoMatchReturnsNoMatch() {
        let plugin = StubPlugin(id: "http", prefix: "GET", confidence: 80)

        // Buffer contains something that doesn't start with "GET".
        let buf = makeBuffer("POST / HTTP/1.1\r\n")
        let outcome = ProtocolDispatcher.selectWinner(
            from: nodes([plugin]),
            buffer: buf,
            context: matchCtx
        )

        if case .noMatch = outcome {
            // Correct — Raw fallback will be used.
        } else {
            XCTFail("Expected .noMatch for unrecognized bytes, got \(outcome)")
        }
    }
}
