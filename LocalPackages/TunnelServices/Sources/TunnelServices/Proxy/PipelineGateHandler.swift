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
public final class PipelineGateHandler: ChannelInboundHandler, RemovableChannelHandler {
    // Accept raw NIOAny — never call unwrapInboundIn (which fatalErrors on type mismatch)
    public typealias InboundIn = NIOAny

    private var buffer: [NIOAny] = []
    private var gateOpen = true
    private weak var savedContext: ChannelHandlerContext?

    public init() {}

    /// Close the gate. All subsequent channelRead data is buffered.
    public func shut() {
        gateOpen = false
    }

    /// Open the gate, flush buffered data, and remove self from pipeline.
    public func openAndRemove() {
        guard let context = savedContext else { return }
        gateOpen = true
        for data in buffer {
            context.fireChannelRead(data)
        }
        buffer.removeAll()
        context.fireChannelReadComplete()
        context.pipeline.removeHandler(self, promise: nil)
    }

    public func handlerAdded(context: ChannelHandlerContext) {
        savedContext = context
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if gateOpen {
            context.fireChannelRead(data)
        } else {
            buffer.append(data)
        }
    }

    public func channelReadComplete(context: ChannelHandlerContext) {
        if gateOpen {
            context.fireChannelReadComplete()
        }
        // When gate is closed, suppress readComplete to avoid confusing downstream
    }
}
