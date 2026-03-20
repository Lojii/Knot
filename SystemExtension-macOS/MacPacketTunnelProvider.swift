import NetworkExtension
import TunnelServices
import Network
import os.log

private let log = Logger(subsystem: "com.KingMap.SystemExtension-macOS", category: "Tunnel")

class MacPacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - Properties

    var mitmServer: MitmService!
    private let captureEngine = PacketCaptureEngine()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.knot.sysext.network")

    // MARK: - Start Tunnel

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("startTunnel called, options=\(String(describing: options))")

        captureEngine.delegate = self

        log.info("startTunnel: calling MitmService.prepare()...")
        guard let server = MitmService.prepare() else {
            log.error("startTunnel: MitmService.prepare() returned nil!")
            let error = NSError(domain: "MacPacketTunnelProvider", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "MitmService.prepare() failed"])
            completionHandler(error)
            return
        }
        mitmServer = server
        log.info("startTunnel: MitmService.prepare() succeeded, task.localIP=\(server.task.localIP), localPort=\(server.task.localPort), localEnable=\(server.task.localEnable)")

        log.info("startTunnel: calling mitmServer.run()...")
        mitmServer.run { [weak self] result in
            switch result {
            case .success:
                log.info("startTunnel: mitmServer.run() succeeded, configuring tunnel...")
                self?.configureTunnel { error in
                    if let error = error {
                        log.error("startTunnel: configureTunnel failed: \(error.localizedDescription)")
                        completionHandler(error)
                        return
                    }
                    log.info("startTunnel: tunnel configured, starting packet capture...")
                    self?.startPacketCapture()
                    self?.startNetworkMonitor()
                    // Initialize QUIC MITM if enabled and task is active
                    if ProxyConfig.HTTP3.enabled {
                        let certPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caCert
                        let keyPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caKey
                        self?.captureEngine.setupQUICMITM(
                            task: server.task,
                            certPath: certPath,
                            keyPath: keyPath
                        )
                        log.info("startTunnel: QUIC MITM initialized (backend: \(ProxyConfig.HTTP3.backend.rawValue))")
                    }
                    log.info("startTunnel: all done, calling completionHandler(nil)")
                    completionHandler(nil)
                }

            case .failure(let error):
                log.error("startTunnel: mitmServer.run() failed: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }

    // MARK: - Configure Tunnel (macOS-specific)

    private func configureTunnel(completionHandler: @escaping (Error?) -> Void) {
        log.info("configureTunnel: building NEPacketTunnelNetworkSettings...")
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: ProxyConfig.VPN.tunnelAddress)
        settings.mtu = ProxyConfig.VPN.mtu

        // HTTP Proxy
        let proxySettings = NEProxySettings()
        proxySettings.httpServer = NEProxyServer(address: ProxyConfig.LocalProxy.host, port: ProxyConfig.LocalProxy.port)
        proxySettings.httpEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: ProxyConfig.LocalProxy.host, port: ProxyConfig.LocalProxy.port)
        proxySettings.httpsEnabled = true
        proxySettings.matchDomains = [""]
        settings.proxySettings = proxySettings

        // IPv4
        let ipv4 = NEIPv4Settings(
            addresses: [ProxyConfig.VPN.ipv4Address],
            subnetMasks: [ProxyConfig.VPN.subnetMask]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        var excludedRoutes = ProxyConfig.VPN.excludedIPv4Routes.map {
            NEIPv4Route(destinationAddress: $0.0, subnetMask: $0.1)
        }
        excludedRoutes.append(NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"))
        excludedRoutes.append(NEIPv4Route(destinationAddress: "224.0.0.0",   subnetMask: "240.0.0.0"))
        ipv4.excludedRoutes = excludedRoutes
        settings.ipv4Settings = ipv4

        // IPv6
        let ipv6 = NEIPv6Settings(
            addresses: [ProxyConfig.VPN.ipv6Address],
            networkPrefixLengths: [64]
        )
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        // DNS
        let dnsSettings = NEDNSSettings(servers: ProxyConfig.VPN.dnsServers)
        dnsSettings.matchDomains = [""]
        dnsSettings.matchDomainsNoSearch = false
        settings.dnsSettings = dnsSettings

        log.info("configureTunnel: calling setTunnelNetworkSettings...")
        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                log.error("configureTunnel: setTunnelNetworkSettings error: \(error.localizedDescription)")
            } else {
                log.info("configureTunnel: setTunnelNetworkSettings succeeded")
            }
            completionHandler(error)
        }
    }

    // MARK: - Packet Capture

    private func startPacketCapture() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }

            for (index, packetData) in packets.enumerated() {
                let protoNumber = protocols[index].uint32Value
                let handled = self.captureEngine.processOutboundPacket(packetData, protocolNumber: protoNumber)
                if !handled {
                    self.packetFlow.writePackets([packetData], withProtocols: [protocols[index]])
                }
            }

            self.startPacketCapture()
        }
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { path in
            log.info("Network path: \(path.status == .satisfied ? "available" : "unavailable")")
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - Stop Tunnel

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stopTunnel called, reason=\(reason.rawValue)")
        pathMonitor.cancel()
        captureEngine.shutdown()
        captureEngine.shutdownQUICMITM()
        mitmServer?.close(completionHandler)
    }

    // MARK: - App Messages

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let command = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil)
            return
        }
        log.info("handleAppMessage: \(command)")
        switch command {
        case "start_pcap":
            let path = MitmService.getStoreFolder() + "capture.pcap"
            captureEngine.startPCAPRecording(filePath: path)
            completionHandler?("pcap_started".data(using: .utf8))
        case "stop_pcap":
            captureEngine.stopPCAPRecording()
            completionHandler?("pcap_stopped".data(using: .utf8))
        case "stats":
            let stats = captureEngine.statistics
            let json = "{\"packets\":\(stats.packets),\"tcp\":\(stats.tcp),\"udp\":\(stats.udp),\"icmp\":\(stats.icmp)}"
            completionHandler?(json.data(using: .utf8))
        case "enable_h3":
            ProxyConfig.HTTP3.enabled = true
            if let task = mitmServer?.task {
                let certPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caCert
                let keyPath = MitmService.getStoreFolder() + ProxyConfig.CertFiles.caKey
                captureEngine.setupQUICMITM(task: task, certPath: certPath, keyPath: keyPath)
            }
            completionHandler?("h3_enabled".data(using: .utf8))
        case "disable_h3":
            ProxyConfig.HTTP3.enabled = false
            captureEngine.shutdownQUICMITM()
            completionHandler?("h3_disabled".data(using: .utf8))
        case "h3_backend_quiche":
            ProxyConfig.HTTP3.backend = .quiche
            completionHandler?("backend_quiche".data(using: .utf8))
        case "h3_backend_lsquic":
            ProxyConfig.HTTP3.backend = .lsquic
            completionHandler?("backend_lsquic".data(using: .utf8))
        case "h3_status":
            let status = "{\"enabled\":\(ProxyConfig.HTTP3.enabled),\"backend\":\"\(ProxyConfig.HTTP3.backend.rawValue)\",\"sessions\":\(captureEngine.quicMITMSessionCount)}"
            completionHandler?(status.data(using: .utf8))
        default:
            completionHandler?(nil)
        }
    }
}

// MARK: - PacketCaptureDelegate

extension MacPacketTunnelProvider: PacketCaptureDelegate {

    func didCapturePacket(_ packet: CapturedPacket) {
        #if DEBUG
        log.debug("PKT \(packet.direction.rawValue) \(packet.decodedProtocol ?? packet.ipPacket.proto.name) \(packet.summary)")
        #endif
    }

    func writePacket(_ data: Data, protocolNumber: UInt32) {
        packetFlow.writePackets([data], withProtocols: [NSNumber(value: protocolNumber)])
    }
}
