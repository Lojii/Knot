import Foundation
import NIO

/// NIO `ChannelInboundHandler` that receives forwarded UDP datagrams from the Helper,
/// decodes the per-datagram destination header, runs protocol detection against the
/// UDP plugin tree, and records each flow via `SessionRecorder`.
///
/// One instance of this handler is added to the single `DatagramChannel` bound by
/// `UDPReceiver`.  All incoming datagrams on that channel arrive here sequentially
/// (on one event-loop thread), so no locking is needed for `senderMap`.
public final class UDPDispatchHandler: ChannelInboundHandler {
    public typealias InboundIn  = AddressedEnvelope<ByteBuffer>
    public typealias InboundOut = AddressedEnvelope<ByteBuffer>

    // MARK: - Constants

    /// How long (seconds) a sender entry is kept after its last datagram.
    private static let idleTimeoutSeconds: Int64 = 30

    // MARK: - Dependencies

    private let task: CaptureTask

    // MARK: - State

    /// Tracks the last-seen timestamp (seconds since epoch) for each sender address.
    /// Used for idle-entry cleanup.
    private var senderLastSeen: [String: TimeInterval] = [:]

    /// Scheduled task that periodically evicts stale sender entries.
    private var cleanupTask: RepeatedTask?

    // MARK: - Init

    public init(task: CaptureTask) {
        self.task = task
    }

    // MARK: - ChannelInboundHandler

    public func channelActive(context: ChannelHandlerContext) {
        // Schedule idle-sender cleanup every `idleTimeoutSeconds` seconds.
        cleanupTask = context.eventLoop.scheduleRepeatedTask(
            initialDelay: .seconds(Self.idleTimeoutSeconds),
            delay:        .seconds(Self.idleTimeoutSeconds)
        ) { [weak self] _ in
            self?.evictStaleSenders()
        }
        context.fireChannelActive()
    }

    public func channelInactive(context: ChannelHandlerContext) {
        cleanupTask?.cancel()
        cleanupTask = nil
        context.fireChannelInactive()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer   = envelope.data
        let sender   = envelope.remoteAddress

        // Track sender for potential response routing.
        let senderKey = sender.description
        senderLastSeen[senderKey] = Date().timeIntervalSince1970

        // Decode the destination header prepended by the Helper.
        guard let header = UDPHeaderCodec.decode(from: &buffer) else {
            AxLogger.log(
                "[UDPDispatchHandler] Failed to decode header from \(senderKey) (\(buffer.readableBytes) bytes)",
                level: .Warning
            )
            return
        }

        let host    = header.host
        let port    = header.port
        let payload = header.payload

        AxLogger.log(
            "[UDPDispatchHandler] datagram \(senderKey) -> \(host):\(port) payload=\(payload.readableBytes)B",
            level: .Info
        )

        // Create a per-flow recorder and populate session fields.
        let recorder = SessionRecorder(task: task)
        recorder.session.host     = host
        recorder.session.schemes  = "UDP"
        recorder.session.methods  = "UDP"
        recorder.session.uri      = "/\(host):\(port)"

        // Run protocol detection against the UDP child nodes.
        let udpNodes = ProtocolRegistry.shared.udpChildren
        let matchCtx = MatchContext(localPort: port, remoteAddress: sender)
        let outcome  = ProtocolDispatcher.selectWinner(from: udpNodes, buffer: payload, context: matchCtx)

        let detectedProtocol: String
        switch outcome {
        case .matched(let node):
            detectedProtocol = node.plugin.displayName
        case .needMoreData, .noMatch:
            detectedProtocol = "UDP"
        }

        // Record the datagram as a minimal flow.
        recorder.session.schemes = detectedProtocol
        recorder.ensureHttpRecorder(
            host:             host,
            port:             port,
            protocolOverride: detectedProtocol,
            method:           "UDP",
            uri:              "/\(host):\(port)",
            extraMetadata:    [
                "udpSender":       senderKey,
                "udpPayloadBytes": payload.readableBytes,
                "udpDstHost":      host,
                "udpDstPort":      port,
            ]
        )

        // Record payload bytes as upload traffic.
        recorder.addUpload(payload.readableBytes)

        // Close the flow immediately (UDP is connectionless).
        recorder.recordClosed()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        AxLogger.log("[UDPDispatchHandler] error: \(error)", level: .Error)
        // Do NOT close the channel — a single bad datagram should not kill the listener.
    }

    // MARK: - Idle Cleanup

    private func evictStaleSenders() {
        let cutoff = Date().timeIntervalSince1970 - TimeInterval(Self.idleTimeoutSeconds)
        let before = senderLastSeen.count
        senderLastSeen = senderLastSeen.filter { $0.value >= cutoff }
        let evicted = before - senderLastSeen.count
        if evicted > 0 {
            AxLogger.log("[UDPDispatchHandler] Evicted \(evicted) stale sender(s)", level: .Info)
        }
    }
}
