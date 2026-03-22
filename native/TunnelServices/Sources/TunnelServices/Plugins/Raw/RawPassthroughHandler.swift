import Foundation
import NIO

// MARK: - RawPassthroughHandler

/// Keeps a raw (unrecognized-protocol) connection open.
/// Records incoming byte counts and calls `recordClosed()` when the channel
/// is finally unregistered from the event loop.
///
/// Originally extracted from the former `ProtocolRouter` so it can be reused
/// by `RawPlugin` and tested independently.
public final class RawPassthroughHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer

    private let recorder: SessionRecorder

    public init(recorder: SessionRecorder) {
        self.recorder = recorder
    }

    // MARK: - ChannelInboundHandler

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        recorder.addUpload(buffer.readableBytes)
        // Data goes nowhere — no target server for unrecognized proxy protocol.
        // The connection stays open until the client closes it.
    }

    public func channelUnregistered(context: ChannelHandlerContext) {
        recorder.recordClosed()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
