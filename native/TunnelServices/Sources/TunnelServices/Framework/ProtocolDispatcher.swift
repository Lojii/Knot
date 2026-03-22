import Foundation
import NIO

// MARK: - ProtocolDispatcher

/// First handler in a NIO pipeline that accumulates bytes, runs all registered
/// plugins against the buffer, picks the highest-confidence winner, builds the
/// winner's pipeline, and then removes itself.
///
/// Fallback behaviour: if no plugin returns `.yes`, a `RawPlugin` handles the
/// connection so every flow is recorded.
public final class ProtocolDispatcher: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn  = ByteBuffer
    public typealias InboundOut = ByteBuffer

    // MARK: - Constants

    /// Maximum bytes accumulated before giving up on protocol detection.
    private static let maxBufferSize = 4 * 1024  // 4 KB

    // MARK: - Dependencies

    private let task:     CaptureTask
    private let nodes:    [ProtocolNode]
    private let recorder: SessionRecorder

    // MARK: - State

    private var pendingBuffer: ByteBuffer?
    private var detectionComplete = false

    // MARK: - Init

    /// - Parameters:
    ///   - task:     The active capture task (used for proxy-enabled checks and recording).
    ///   - nodes:    Ordered list of protocol nodes to evaluate (e.g. `tcpChildren`).
    ///   - recorder: Session recorder used for error / closed events.
    /// Metadata from the outer protocol (e.g., CONNECT target host/port).
    /// Propagated to ProtocolContext so inner plugins can use it.
    private let outerMetadata: ProtocolMetadata

    public init(task: CaptureTask, nodes: [ProtocolNode], recorder: SessionRecorder,
                metadata: ProtocolMetadata = .empty) {
        self.task     = task
        self.nodes    = nodes
        self.recorder = recorder
        self.outerMetadata = metadata
    }

    // MARK: - ChannelInboundHandler

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !detectionComplete else {
            context.fireChannelRead(data)
            return
        }

        // 1. Proxy-enabled check (formerly in ProtocolRouter).
        if let local = context.channel.localAddress?.description {
            let isLocal = local.contains(ProxyConfig.LocalProxy.host)
            if (isLocal && task.localEnable == 0) || (!isLocal && task.wifiEnable == 0) {
                context.close(promise: nil)
                return
            }
        }

        // 2. Accumulate bytes.
        //    Guard: IOData from decoder removal has description "IOData { ByteBuffer ... }"
        //    which will fatalError in unwrapInboundIn expecting ByteBuffer.
        let desc = data.description
        if desc.hasPrefix("IOData") || desc.hasPrefix("FileRegion") {
            AxLogger.log("[ProtocolDispatcher] absorbed IOData from decoder removal", level: .Warning)
            return
        }
        var incoming = unwrapInboundIn(data)
        if pendingBuffer == nil {
            pendingBuffer = context.channel.allocator.buffer(capacity: incoming.readableBytes)
        }
        pendingBuffer?.writeBuffer(&incoming)

        // 3. Enforce max-buffer cap.
        if (pendingBuffer?.readableBytes ?? 0) > Self.maxBufferSize {
            AxLogger.log(
                "[ProtocolDispatcher] buffer exceeded \(Self.maxBufferSize) bytes — falling back to Raw",
                level: .Warning
            )
            dispatchToRaw(context: context)
            return
        }

        // 4. Run detection.
        attemptDetection(context: context)
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if !detectionComplete {
            recorder.recordClosed()
        }
        context.fireChannelInactive()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        if !detectionComplete {
            recorder.recordError(error.localizedDescription)
        }
        context.close(promise: nil)
    }

    // MARK: - Detection Logic

    private func attemptDetection(context: ChannelHandlerContext) {
        guard let buf = pendingBuffer else { return }

        let matchCtx = MatchContext(
            localPort:  context.channel.localAddress.flatMap({ $0.port }) ?? 0,
            remoteAddress: context.channel.remoteAddress
        )

        let outcome = Self.selectWinner(from: nodes, buffer: buf, context: matchCtx)

        switch outcome {
        case .matched(let node):
            dispatch(to: node, context: context)
        case .needMoreData:
            // Wait for more data — buffer is still below 4 KB cap.
            return
        case .noMatch:
            // No plugin matched and none needs more data — use Raw fallback.
            dispatchToRaw(context: context)
        }
    }

    // MARK: - Winner Selection (internal for testing)

    enum SelectionOutcome {
        case matched(ProtocolNode)
        case needMoreData
        case noMatch
    }

    /// Pure selection logic, exposed as a static method so tests can exercise
    /// it without a real NIO channel.
    static func selectWinner(
        from nodes: [ProtocolNode],
        buffer: ByteBuffer,
        context: MatchContext
    ) -> SelectionOutcome {
        var winner:    ProtocolNode? = nil
        var winnerConf = -1
        var needMore   = false

        for node in nodes {
            switch node.plugin.canMatch(buffer, context: context) {
            case .yes(let conf):
                if conf > winnerConf {
                    winnerConf = conf
                    winner     = node
                }
            case .no:
                break
            case .needMoreData:
                needMore = true
            }
        }

        if let winner = winner {
            return .matched(winner)
        } else if needMore {
            return .needMoreData
        } else {
            return .noMatch
        }
    }

    // MARK: - Dispatch Helpers

    private func dispatch(to node: ProtocolNode, context: ChannelHandlerContext) {
        detectionComplete = true
        AxLogger.log("[ProtocolDispatcher] detected protocol: \(node.plugin.id) (\(node.plugin.displayName)), remote=\(context.channel.remoteAddress?.description ?? "?"), outerMetadata.innerHost=\(outerMetadata.innerHost ?? "nil"), pendingBytes=\(pendingBuffer?.readableBytes ?? 0)", level: .Warning)

        let protoCtx = ProtocolContext(
            channel:       context.channel,
            task:          task,
            recorder:      recorder,
            childNodes:    node.children,
            metadata:      outerMetadata,
            initialBuffer: pendingBuffer
        )

        let future = node.plugin.buildPipeline(context: protoCtx)

        future.hop(to: context.eventLoop).whenComplete { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                // Forward accumulated bytes into the newly built pipeline.
                if var buf = self.pendingBuffer {
                    let copy = buf.readSlice(length: buf.readableBytes) ?? buf
                    context.fireChannelRead(self.wrapInboundOut(copy))
                }
                context.pipeline.removeHandler(self, promise: nil)

            case .failure(let error):
                AxLogger.log(
                    "[ProtocolDispatcher] buildPipeline failed for \(node.plugin.id): \(error)",
                    level: .Error
                )
                self.recorder.recordError(error.localizedDescription)
                context.close(promise: nil)
            }
        }
    }

    private func dispatchToRaw(context: ChannelHandlerContext) {
        let rawNode = ProtocolNode(plugin: RawPlugin())
        dispatch(to: rawNode, context: context)
    }
}

// MARK: - SocketAddress convenience

private extension SocketAddress {
    var port: Int? {
        switch self {
        case .v4(let addr): return Int(addr.address.sin_port.bigEndian)
        case .v6(let addr): return Int(addr.address.sin6_port.bigEndian)
        case .unixDomainSocket: return nil
        }
    }
}
