//
//  UDPForwarder.swift
//  TunnelServices
//
//  Forwards UDP packets to their destination and returns responses.
//  Uses Network.framework NWConnection for UDP communication.
//

import Foundation
import Network

public class UDPForwarder {

    /// Represents a pending UDP exchange (request → response).
    private struct PendingExchange {
        let originalPacket: IPPacket
        let sendTime: Date
        let completion: (Data?) -> Void
    }

    private let queue = DispatchQueue(label: "com.knot.udp.forwarder")
    private var connections = [String: NWConnection]()  // key = "host:port"
    private var pendingExchanges = [String: PendingExchange]()

    public init() {}

    /// Forward a UDP packet to its destination and call completion with the response payload.
    public func forward(packet: IPPacket, completion: @escaping (Data?) -> Void) {
        guard let udp = packet.udpHeader else {
            completion(nil)
            return
        }

        let host = packet.destinationIP
        let port = udp.destinationPort
        let key = "\(host):\(port)"

        let appData = packet.applicationData
        guard !appData.isEmpty else {
            completion(nil)
            return
        }

        queue.async { [weak self] in
            self?.sendUDP(host: host, port: port, data: appData, key: key, packet: packet, completion: completion)
        }
    }

    private func sendUDP(host: String, port: UInt16, data: Data, key: String, packet: IPPacket, completion: @escaping (Data?) -> Void) {
        // Get or create connection
        let connection: NWConnection
        if let existing = connections[key], existing.state == .ready {
            connection = existing
        } else {
            connections[key]?.cancel()
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let newConn = NWConnection(host: nwHost, port: nwPort, using: .udp)
            newConn.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.connections.removeValue(forKey: key)
                }
            }
            newConn.start(queue: queue)
            connections[key] = newConn
            connection = newConn
        }

        // Store pending exchange
        pendingExchanges[key] = PendingExchange(originalPacket: packet, sendTime: Date(), completion: completion)

        // Send data
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                AxLogger.log("UDP send error to \(key): \(error)", level: .Error)
                self?.pendingExchanges.removeValue(forKey: key)
                completion(nil)
                return
            }

            // Receive response
            connection.receiveMessage { [weak self] content, _, _, error in
                self?.pendingExchanges.removeValue(forKey: key)
                if let error = error {
                    AxLogger.log("UDP receive error from \(key): \(error)", level: .Error)
                    completion(nil)
                    return
                }
                completion(content)
            }
        })

        // Timeout: clean up after 5 seconds
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.pendingExchanges[key] != nil {
                self?.pendingExchanges.removeValue(forKey: key)
                // Don't call completion again if already called
            }
        }
    }

    /// Send raw UDP data to a specific host:port and call completion with the response.
    /// Used by QUIC MITM to forward server-bound packets without an IPPacket.
    public func sendRaw(data: Data, host: String, port: UInt16, completion: @escaping (Data?) -> Void) {
        let key = "\(host):\(port)"
        queue.async { [weak self] in
            guard let self = self else { completion(nil); return }

            // Get or create connection (same pool as forward())
            let connection: NWConnection
            if let existing = self.connections[key], existing.state == .ready {
                connection = existing
            } else {
                self.connections[key]?.cancel()
                let nwHost = NWEndpoint.Host(host)
                let nwPort = NWEndpoint.Port(rawValue: port)!
                let newConn = NWConnection(host: nwHost, port: nwPort, using: .udp)
                newConn.stateUpdateHandler = { [weak self] state in
                    if case .failed = state {
                        self?.connections.removeValue(forKey: key)
                    }
                }
                newConn.start(queue: self.queue)
                self.connections[key] = newConn
                connection = newConn
            }

            // Send and receive (no PendingExchange tracking needed)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    AxLogger.log("UDP sendRaw error to \(key): \(error)", level: .Error)
                    completion(nil)
                    return
                }
                connection.receiveMessage { content, _, _, error in
                    if let error = error {
                        AxLogger.log("UDP sendRaw receive error from \(key): \(error)", level: .Error)
                        completion(nil)
                        return
                    }
                    completion(content)
                }
            })
        }
    }

    /// Cancel all connections and clean up.
    public func shutdown() {
        queue.async { [weak self] in
            self?.connections.values.forEach { $0.cancel() }
            self?.connections.removeAll()
            self?.pendingExchanges.removeAll()
        }
    }
}
