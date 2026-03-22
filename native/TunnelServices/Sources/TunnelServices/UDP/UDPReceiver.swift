import Foundation
import NIO

/// Lightweight wrapper around a NIO `DatagramBootstrap` that listens on a UDP port
/// and feeds all received datagrams through `UDPDispatchHandler`.
public final class UDPReceiver {

    private var channel: Channel?

    public init() {}

    /// Start listening for UDP datagrams on `host:port`.
    ///
    /// - Parameters:
    ///   - group: The `EventLoopGroup` to run the channel on.
    ///   - task:  The active capture task, forwarded to each `UDPDispatchHandler`.
    ///   - port:  UDP port to bind on `127.0.0.1`.
    public func start(group: EventLoopGroup, task: CaptureTask, port: Int) throws {
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(UDPDispatchHandler(task: task))
            }
        channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
        AxLogger.log("[UDPReceiver] Bound on 127.0.0.1:\(port)", level: .Info)
    }

    /// Close the UDP channel. Safe to call even if `start` was never called.
    public func stop() {
        channel?.close(promise: nil)
        channel = nil
        AxLogger.log("[UDPReceiver] Stopped", level: .Info)
    }
}
