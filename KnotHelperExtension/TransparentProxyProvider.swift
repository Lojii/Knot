//
//  TransparentProxyProvider.swift
//  KnotHelperExtension
//
//  Created by Claude on 2026/3/21.
//  Copyright © 2026 Lojii. All rights reserved.
//

import NetworkExtension
import os.log

private let log = Logger(subsystem: "com.KingMap.KnotHelper.Extension", category: "Proxy")

class TransparentProxyProvider: NETransparentProxyProvider {

    // MARK: - Configuration

    private var shouldForwardTCP = true
    private var shouldForwardUDP = true
    private var targetPort: Int = 8034

    /// Bundle IDs excluded from proxying to prevent infinite loops.
    private let excludedBundleIDs: Set<String> = [
        "com.KingMap.KnotApp-macOS",
        "com.KingMap.KnotHelper",
        "com.KingMap.KnotHelper.Extension",
    ]

    // MARK: - Lifecycle

    override func startProxy(options: [String: Any]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("startProxy called, options=\(String(describing: options))")
        loadConfig()
        log.info("Config loaded: tcp=\(self.shouldForwardTCP), udp=\(self.shouldForwardUDP), port=\(self.targetPort)")
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stopProxy called, reason=\(String(describing: reason))")
        completionHandler()
    }

    // MARK: - Flow Handling

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let tcpFlow = flow as? NEAppProxyTCPFlow else { return false }
        guard shouldForwardTCP else {
            log.debug("TCP forwarding disabled, rejecting flow")
            return false
        }
        guard !isExcluded(flow) else { return false }

        let handler = TCPFlowHandler(flow: tcpFlow, targetPort: targetPort)
        handler.start()
        return true
    }

    override func handleNewUDPFlow(_ flow: NEAppProxyUDPFlow,
                                    initialRemoteEndpoint remoteEndpoint: NWEndpoint) -> Bool {
        guard shouldForwardUDP else {
            log.debug("UDP forwarding disabled, rejecting flow")
            return false
        }
        guard !isExcluded(flow) else { return false }

        let handler = UDPFlowHandler(flow: flow, targetPort: targetPort)
        handler.start()
        return true
    }

    // MARK: - Anti-loop

    private func isExcluded(_ flow: NEAppProxyFlow) -> Bool {
        let sourceID = flow.metaData.sourceAppSigningIdentifier
        if excludedBundleIDs.contains(sourceID) {
            log.debug("Excluding flow from \(sourceID) (bundle exclusion)")
            return true
        }

        // Check if the remote endpoint is localhost to prevent loops
        if let endpoint = (flow as? NEAppProxyTCPFlow)?.remoteEndpoint as? NWHostEndpoint {
            if isLocalhost(endpoint.hostname) {
                log.debug("Excluding flow to localhost \(endpoint.hostname)")
                return true
            }
        }

        return false
    }

    private func isLocalhost(_ hostname: String) -> Bool {
        if hostname.hasPrefix("127.") { return true }
        if hostname == "::1" { return true }
        if hostname == "localhost" { return true }
        return false
    }

    // MARK: - Configuration Loading

    private func loadConfig() {
        guard let defaults = UserDefaults(suiteName: "group.Lojii.NIO1901") else {
            log.warning("Failed to open App Group UserDefaults, using defaults")
            return
        }

        if defaults.object(forKey: "helper.forwardTCP") != nil {
            shouldForwardTCP = defaults.bool(forKey: "helper.forwardTCP")
        }
        if defaults.object(forKey: "helper.forwardUDP") != nil {
            shouldForwardUDP = defaults.bool(forKey: "helper.forwardUDP")
        }
        if defaults.object(forKey: "helper.port") != nil {
            let port = defaults.integer(forKey: "helper.port")
            if port > 0 && port <= 65535 {
                targetPort = port
            }
        }
    }
}
