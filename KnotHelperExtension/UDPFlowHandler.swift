//
//  UDPFlowHandler.swift
//  KnotHelperExtension
//
//  Created by Claude on 2026/3/21.
//  Copyright © 2026 Lojii. All rights reserved.
//

import NetworkExtension
import Network
import NIOCore
import TunnelServices
import os.log

private let log = Logger(subsystem: "com.KingMap.KnotHelper.Extension", category: "UDPFlow")

/// Handles a single UDP flow by forwarding datagrams with destination headers
/// through a local proxy connection.
final class UDPFlowHandler {

    private let flow: NEAppProxyUDPFlow
    private let targetPort: Int
    private var connection: NWConnection?
    private var isClosed = false

    /// Idle timeout: close the flow after 30 seconds of inactivity.
    private static let idleTimeoutSeconds: TimeInterval = 30
    private var idleTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.knot.udpflow.timer")

    init(flow: NEAppProxyUDPFlow, targetPort: Int) {
        self.flow = flow
        self.targetPort = targetPort
    }

    // MARK: - Public

    func start() {
        flow.open(withLocalEndpoint: nil) { [weak self] error in
            if let error = error {
                log.error("Failed to open UDP flow: \(error.localizedDescription)")
                self?.closeAll()
                return
            }
            self?.connectToProxy()
        }
    }

    // MARK: - Connection Setup

    private func connectToProxy() {
        let nwHost = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(targetPort))
        let params = NWParameters.udp
        params.prohibitExpensivePaths = false
        params.prohibitConstrainedPaths = false

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                log.debug("UDP proxy connection ready")
                self.resetIdleTimer()
                self.readFromFlow()
                self.readFromConnection()
            case .failed(let error):
                log.error("UDP proxy connection failed: \(error.localizedDescription)")
                self.closeAll()
            case .cancelled:
                log.debug("UDP proxy connection cancelled")
            default:
                break
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
    }

    // MARK: - Flow → Proxy

    /// Read datagrams from the NEAppProxyUDPFlow, encode headers, and send to proxy.
    private func readFromFlow() {
        guard !isClosed else { return }

        flow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self = self, !self.isClosed else { return }

            if let error = error {
                log.debug("UDP flow read error: \(error.localizedDescription)")
                self.closeAll()
                return
            }

            guard let datagrams = datagrams, let endpoints = endpoints,
                  !datagrams.isEmpty else {
                log.debug("UDP flow EOF")
                self.closeAll()
                return
            }

            self.resetIdleTimer()

            // Send each datagram with its destination header
            let group = DispatchGroup()
            var sendError: Error?

            for (datagram, endpoint) in zip(datagrams, endpoints) {
                guard let hostEndpoint = endpoint as? NWHostEndpoint else { continue }

                let host = hostEndpoint.hostname
                let port = Int(hostEndpoint.port) ?? 0

                // Encode header + payload using UDPHeaderCodec
                var buffer = ByteBufferAllocator().buffer(capacity: datagram.count + 64)
                UDPHeaderCodec.encode(host: host, port: port, into: &buffer)
                buffer.writeBytes(datagram)

                let encoded = Data(buffer.readableBytesView)

                group.enter()
                self.connection?.send(content: encoded, completion: .contentProcessed({ error in
                    if let error = error {
                        sendError = error
                    }
                    group.leave()
                }))
            }

            group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
                if let error = sendError {
                    log.debug("UDP send error: \(error.localizedDescription)")
                    self?.closeAll()
                    return
                }
                self?.readFromFlow()
            }
        }
    }

    // MARK: - Proxy → Flow

    /// Read messages from the proxy connection, decode headers, and write back to the flow.
    private func readFromConnection() {
        guard !isClosed else { return }

        connection?.receiveMessage { [weak self] content, _, isComplete, error in
            guard let self = self, !self.isClosed else { return }

            if let error = error {
                log.debug("UDP connection read error: \(error.localizedDescription)")
                self.closeAll()
                return
            }

            guard let data = content, !data.isEmpty else {
                if isComplete {
                    log.debug("UDP connection EOF")
                    self.closeAll()
                }
                return
            }

            self.resetIdleTimer()

            // Decode header to extract destination
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeBytes(data)

            guard let decoded = UDPHeaderCodec.decode(from: &buffer) else {
                log.warning("Failed to decode UDP header from proxy response")
                self.readFromConnection()
                return
            }

            let payload = Data(decoded.payload.readableBytesView)
            let endpoint = NWHostEndpoint(hostname: decoded.host, port: String(decoded.port))

            self.flow.writeDatagrams([payload], sentBy: [endpoint]) { [weak self] error in
                if let error = error {
                    log.debug("UDP flow write error: \(error.localizedDescription)")
                    self?.closeAll()
                    return
                }
                self?.readFromConnection()
            }
        }
    }

    // MARK: - Idle Timer

    private func resetIdleTimer() {
        idleTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + Self.idleTimeoutSeconds)
        timer.setEventHandler { [weak self] in
            log.debug("UDP flow idle timeout, closing")
            self?.closeAll()
        }
        timer.resume()
        idleTimer = timer
    }

    // MARK: - Cleanup

    private func closeAll() {
        guard !isClosed else { return }
        isClosed = true

        idleTimer?.cancel()
        idleTimer = nil

        connection?.cancel()
        connection = nil

        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)

        log.debug("UDP flow handler closed")
    }
}
