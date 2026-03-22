import NIOCore
import NIOWebSocket

final class WebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let pushManager: LivePushManager

    init(pushManager: LivePushManager) {
        self.pushManager = pushManager
    }

    func handlerAdded(context: ChannelHandlerContext) {
        pushManager.addConnection(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        pushManager.removeConnection(context.channel)
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)

        case .connectionClose:
            pushManager.removeConnection(context.channel)
            let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(close)).whenComplete { _ in
                context.close(promise: nil)
            }

        case .text, .binary, .pong:
            // Push-only: ignore inbound data frames
            break

        default:
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        pushManager.removeConnection(context.channel)
        context.close(promise: nil)
    }
}
