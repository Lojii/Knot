//
//  HelperViewModel.swift
//  KnotHelper
//
//  Copyright © 2026 Lojii. All rights reserved.
//

import Foundation
import NetworkExtension
import SystemExtensions
import Combine
import TunnelServices

private let appGroupID = "group.Lojii.NIO1901"
private let extensionBundleID = "com.KingMap.KnotHelper.Extension"

@MainActor
final class HelperViewModel: ObservableObject {

    // MARK: - Published state

    @Published var isRunning: Bool = false
    @Published var forwardTCP: Bool = true
    @Published var forwardUDP: Bool = true
    @Published var portText: String = "9090"
    @Published var statusText: String = "Stopped"
    @Published var mainAppRunning: Bool = false

    // MARK: - Private

    private let defaults = UserDefaults(suiteName: appGroupID)
    private var ipc: AppGroupIPC?

    // MARK: - Init

    init() {
        loadDefaults()
        setupIPC()
    }

    // MARK: - Public actions

    func toggleEnabled() {
        if isRunning {
            stopProxy()
        } else {
            installAndStart()
        }
    }

    func commitConfig() {
        defaults?.set(forwardTCP, forKey: "ipc_helper.forwardTCP")
        defaults?.set(forwardUDP, forKey: "ipc_helper.forwardUDP")
        defaults?.set(portText, forKey: "ipc_helper.port")
        defaults?.synchronize()
        ipc?.passMessage(forwardTCP, identifier: "helper.forwardTCP")
        ipc?.passMessage(forwardUDP, identifier: "helper.forwardUDP")
        ipc?.passMessage(portText, identifier: "helper.port")
    }

    // MARK: - Private helpers

    private func loadDefaults() {
        forwardTCP = defaults?.bool(forKey: "ipc_helper.forwardTCP") ?? true
        forwardUDP = defaults?.bool(forKey: "ipc_helper.forwardUDP") ?? true
        portText   = defaults?.string(forKey: "ipc_helper.port") ?? "9090"
    }

    private func setupIPC() {
        let ipcInstance = AppGroupIPC(groupIdentifier: appGroupID)
        self.ipc = ipcInstance
        ipcInstance.listenForMessage(identifier: "app.status") { [weak self] value in
            Task { @MainActor in
                self?.mainAppRunning = (value as? Bool) ?? false
            }
        }
    }

    // MARK: - Extension lifecycle

    private func installAndStart() {
        statusText = "Installing…"
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main
        )
        request.delegate = ExtensionDelegate(owner: self)
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    fileprivate func activationDidSucceed() {
        configureAndStartProxy()
    }

    fileprivate func activationDidFail(_ error: Error) {
        statusText = "Install failed: \(error.localizedDescription)"
    }

    private func configureAndStartProxy() {
        NETransparentProxyManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self else { return }
            Task { @MainActor in
                let manager = managers?.first ?? NETransparentProxyManager()
                self.applyConfig(to: manager)
                do {
                    try await manager.saveToPreferences()
                    try await manager.loadFromPreferences()
                    try manager.connection.startVPNTunnel()
                    self.isRunning = true
                    self.statusText = "Running"
                    self.ipc?.passMessage(true, identifier: "helper.enabled")
                    self.ipc?.passMessage(self.statusText, identifier: "helper.status")
                    self.commitConfig()
                } catch {
                    self.statusText = "Start failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func applyConfig(to manager: NETransparentProxyManager) {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = extensionBundleID
        proto.serverAddress = "KnotHelper"
        manager.protocolConfiguration = proto
        manager.localizedDescription = "KnotHelper Proxy"
        manager.isEnabled = true
    }

    private func stopProxy() {
        NETransparentProxyManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self else { return }
            Task { @MainActor in
                managers?.first?.connection.stopVPNTunnel()
                self.isRunning = false
                self.statusText = "Stopped"
                self.ipc?.passMessage(false, identifier: "helper.enabled")
                self.ipc?.passMessage(self.statusText, identifier: "helper.status")
            }
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate (off main-actor)

private final class ExtensionDelegate: NSObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    private weak var owner: HelperViewModel?

    init(owner: HelperViewModel) {
        self.owner = owner
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor [weak owner] in
            owner?.statusText = "Awaiting user approval…"
        }
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor [weak owner] in
            owner?.activationDidSucceed()
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor [weak owner] in
            owner?.activationDidFail(error)
        }
    }
}

// MARK: - AppGroupIPC availability shim
// AppGroupIPC is defined in TunnelServices; imported via the KnotHelper target's package dependency.
