import Foundation
import NIOCore
import NIOConcurrencyHelpers
import NIOWebSocket

public final class LivePushManager {

    private let connections = NIOLockedValueBox<[ObjectIdentifier: Channel]>([:])

    public init() {}

    // MARK: - Connection management

    func addConnection(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        connections.withLockedValue { $0[id] = channel }
    }

    func removeConnection(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        connections.withLockedValue { _ = $0.removeValue(forKey: id) }
    }

    public var hasClients: Bool {
        connections.withLockedValue { !$0.isEmpty }
    }

    // MARK: - LiveBridge integration

    public func attach(_ bridge: LiveBridge) {
        bridge.onNewFlow = { [weak self] data in
            self?.broadcast(type: "flow", data: data)
        }
        bridge.onFlowUpdate = { [weak self] data in
            self?.broadcast(type: "flow_update", data: data)
        }
        bridge.onMetrics = { [weak self] data in
            self?.broadcast(type: "metrics", data: data)
        }
        bridge.onStats = { [weak self] data in
            self?.broadcast(type: "stats", data: data)
        }
        bridge.onRetest = { [weak self] data in
            self?.broadcast(type: "retest", data: data)
        }
        bridge.onSurfProgress = { [weak self] data in
            self?.broadcast(type: "surf_progress", data: data)
        }
    }

    public func detach(_ bridge: LiveBridge) {
        bridge.onNewFlow = nil
        bridge.onFlowUpdate = nil
        bridge.onMetrics = nil
        bridge.onStats = nil
        bridge.onRetest = nil
        bridge.onSurfProgress = nil
    }

    // MARK: - Broadcast

    func broadcast(type: String, data: [String: Any]) {
        let message: [String: Any] = ["type": type, "data": data]
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: message, options: [])
        } catch {
            return
        }

        let channels = connections.withLockedValue { Array($0.values) }
        for channel in channels {
            var buffer = channel.allocator.buffer(capacity: jsonData.count)
            buffer.writeBytes(jsonData)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            channel.writeAndFlush(frame, promise: nil)
        }
    }
}
