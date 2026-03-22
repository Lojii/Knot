import NIO

/// A pipeline handler that can buffer all inbound data during pipeline reconfiguration.
///
/// Usage pattern:
/// 1. Add gate at the END of the pipeline (syncOperations)
/// 2. Close the gate — all subsequent channelRead data is buffered
/// 3. Remove/add other handlers freely — IOData from decoder removal is safely buffered
/// 4. Open the gate — flush buffered data to the (now correct) pipeline, then remove self
///
/// This solves the NIO pipeline reconfiguration race condition where
/// ByteToMessageHandler forwards leftover bytes as IOData during removal,
/// and those bytes reach a handler expecting a different type (causing fatalError).
public final class PipelineGateHandler: ChannelDuplexHandler, RemovableChannelHandler {
    // Accept raw NIOAny in both directions
    public typealias InboundIn = NIOAny
    public typealias InboundOut = NIOAny
    public typealias OutboundIn = NIOAny
    public typealias OutboundOut = NIOAny

    private var inboundBuffer: [NIOAny] = []
    private var outboundBuffer: [(NIOAny, EventLoopPromise<Void>?)] = []
    private var gateOpen = true
    private weak var savedContext: ChannelHandlerContext?

    public init() {}

    /// Close the gate. All subsequent inbound/outbound data is buffered.
    public func shut() {
        gateOpen = false
    }

    /// Open the gate, flush buffered data, and remove self from pipeline.
    public func openAndRemove() {
        guard let context = savedContext else { return }
        gateOpen = true
        // Flush outbound first (writes waiting to go to network)
        for (data, promise) in outboundBuffer {
            context.write(data, promise: promise)
        }
        outboundBuffer.removeAll()
        if !outboundBuffer.isEmpty { context.flush() }
        // Then flush inbound (reads waiting to go to handlers)
        for data in inboundBuffer {
            context.fireChannelRead(data)
        }
        inboundBuffer.removeAll()
        context.fireChannelReadComplete()
        context.pipeline.removeHandler(self, promise: nil)
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        savedContext = context
    }

    // MARK: - Inbound

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if gateOpen {
            context.fireChannelRead(data)
        } else {
            inboundBuffer.append(data)
        }
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        if gateOpen {
            context.fireChannelReadComplete()
        }
    }

    // MARK: - Outbound

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if gateOpen {
            context.write(data, promise: promise)
        } else {
            outboundBuffer.append((data, promise))
        }
    }

    public func flush(context: ChannelHandlerContext) {
        if gateOpen {
            context.flush()
        }
    }
}
