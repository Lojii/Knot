//
//  TCPFlowHandler.swift
//  KnotHelperExtension
//
//  Created by Claude on 2026/3/21.
//  Copyright © 2026 Lojii. All rights reserved.
//

import NetworkExtension
import Network
import os.log

private let log = Logger(subsystem: "com.KingMap.KnotHelper.Extension", category: "TCPFlow")

/// Handles a single TCP flow by relaying traffic through an HTTP CONNECT tunnel
/// to the local proxy server.
final class TCPFlowHandler {

    private let flow: NEAppProxyTCPFlow
    private let targetPort: Int
    private var connection: NWConnection?
    private var isClosed = false

    init(flow: NEAppProxyTCPFlow, targetPort: Int) {
        self.flow = flow
        self.targetPort = targetPort
    }

    // MARK: - Public

    func start() {
        flow.open(withLocalEndpoint: nil) { [weak self] error in
            if let error = error {
                log.error("Failed to open TCP flow: \(error.localizedDescription)")
                self?.closeAll()
                return
            }
            self?.connectToProxy()
        }
    }

    // MARK: - Connection Setup

    private func connectToProxy() {
        guard let remoteEndpoint = flow.remoteEndpoint as? NWHostEndpoint else {
            log.error("TCP flow has no remote endpoint")
            closeAll()
            return
        }

        let host = remoteEndpoint.hostname
        let port = remoteEndpoint.port

        log.debug("TCP flow to \(host):\(port), connecting to proxy at 127.0.0.1:\(self.targetPort)")

        let nwHost = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(targetPort))
        let params = NWParameters.tcp
        params.prohibitExpensivePaths = false
        params.prohibitConstrainedPaths = false

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                log.debug("Proxy connection ready, sending CONNECT for \(host):\(port)")
                self.sendConnect(host: host, port: port)
            case .failed(let error):
                log.error("Proxy connection failed: \(error.localizedDescription)")
                self.closeAll()
            case .cancelled:
                log.debug("Proxy connection cancelled")
            default:
                break
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
    }

    // MARK: - HTTP CONNECT Handshake

    private func sendConnect(host: String, port: String) {
        let connectRequest = "CONNECT \(host):\(port) HTTP/1.1\r\nHost: \(host):\(port)\r\n\r\n"
        guard let data = connectRequest.data(using: .utf8) else {
            log.error("Failed to encode CONNECT request")
            closeAll()
            return
        }

        connection?.send(content: data, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                log.error("Failed to send CONNECT: \(error.localizedDescription)")
                self?.closeAll()
                return
            }
            self?.receiveConnectResponse()
        }))
    }

    private func receiveConnectResponse() {
        // Read up to 4KB for the CONNECT response
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, _, error in
            guard let self = self else { return }

            if let error = error {
                log.error("Error receiving CONNECT response: \(error.localizedDescription)")
                self.closeAll()
                return
            }

            guard let data = content, let response = String(data: data, encoding: .utf8) else {
                log.error("Empty or non-UTF8 CONNECT response")
                self.closeAll()
                return
            }

            if response.contains("200") {
                log.debug("CONNECT handshake succeeded")
                self.startBidirectionalRelay()
            } else {
                log.error("CONNECT handshake failed: \(response.prefix(200))")
                self.closeAll()
            }
        }
    }

    // MARK: - Bidirectional Relay

    private func startBidirectionalRelay() {
        readFromFlow()
        readFromConnection()
    }

    /// Read data from the NEAppProxyTCPFlow and send to the NWConnection.
    private func readFromFlow() {
        guard !isClosed else { return }

        flow.readData { [weak self] data, error in
            guard let self = self, !self.isClosed else { return }

            if let error = error {
                log.debug("Flow read error (closing): \(error.localizedDescription)")
                self.closeAll()
                return
            }

            guard let data = data, !data.isEmpty else {
                log.debug("Flow EOF, closing")
                self.closeAll()
                return
            }

            self.connection?.send(content: data, completion: .contentProcessed({ [weak self] error in
                if let error = error {
                    log.debug("Connection send error: \(error.localizedDescription)")
                    self?.closeAll()
                    return
                }
                self?.readFromFlow()
            }))
        }
    }

    /// Read data from the NWConnection and write to the NEAppProxyTCPFlow.
    private func readFromConnection() {
        guard !isClosed else { return }

        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self, !self.isClosed else { return }

            if let error = error {
                log.debug("Connection read error: \(error.localizedDescription)")
                self.closeAll()
                return
            }

            if let data = content, !data.isEmpty {
                self.flow.write(data) { [weak self] error in
                    if let error = error {
                        log.debug("Flow write error: \(error.localizedDescription)")
                        self?.closeAll()
                        return
                    }
                    self?.readFromConnection()
                }
            } else if isComplete {
                log.debug("Connection EOF, closing")
                self.closeAll()
            } else {
                self.readFromConnection()
            }
        }
    }

    // MARK: - Cleanup

    private func closeAll() {
        guard !isClosed else { return }
        isClosed = true

        connection?.cancel()
        connection = nil

        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)

        log.debug("TCP flow handler closed")
    }
}
