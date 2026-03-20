import Foundation
import NIO

// MARK: - RawPlugin

/// Fallback plugin that accepts any unrecognized protocol with the lowest
/// possible confidence (0). It records a minimal raw connection entry and
/// installs a `RawPassthroughHandler` to track byte counts until close.
public final class RawPlugin: ProtocolPlugin {

    public let id          = "raw"
    public let displayName = "Raw"

    public init() {}

    // MARK: - ProtocolPlugin

    /// Always matches — confidence 0 so any real plugin wins.
    public func canMatch(_ buffer: ByteBuffer, context: MatchContext) -> MatchResult {
        return .yes(confidence: 0)
    }

    /// Records the raw connection then adds `RawPassthroughHandler`.
    public func buildPipeline(context: ProtocolContext) -> EventLoopFuture<Void> {
        let recorder = context.recorder
        let channel  = context.channel

        // Record first bytes if available.
        let firstBytes: Data
        if let buf = context.initialBuffer {
            firstBytes = Data(buffer: buf)
        } else {
            firstBytes = Data()
        }

        let peer  = channel.remoteAddress?.description
        let local = channel.localAddress?.description
        recorder.recordRawConnection(
            peerAddress:  peer,
            localAddress: local,
            firstBytes:   firstBytes
        )

        return channel.pipeline.addHandler(
            RawPassthroughHandler(recorder: recorder),
            name: "raw.passthrough"
        )
    }

    /// Raw connections have no protocol-specific recorder.
    public func createRecorder(flowId: String, context: ProtocolContext) -> ProtocolRecorder? {
        return nil
    }
}
