//
//  NEManager.swift
//  NEManager
//
//  Created by LiuJie on 2022/3/21.
//

import Foundation
import NetworkExtension
//import NIOMan

extension NEManager {
    public static var bundleID = "lojii.nio.2022"
    public static var bundleIDTunnel = "\(bundleID).Tunnel"
    public static var groupID = "group.\(bundleID)"
}

public final class NEManager {
    public typealias Handler = (Error?) -> Void
    public static let shared = NEManager()
    public var statusDidChangeHandler: ((Status) -> Void)?
    public private(set) var tunnel: NETunnelProviderManager?

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(vpnDidChange(noti:)), name: NSNotification.Name.NEVPNStatusDidChange, object: nil)
    }
}

public extension NEManager {
    
    func loadCurrentStatus(completion:@escaping (Status) -> Void) {
        if let manager = tunnel {
            completion(Status(manager.connection.status))
        }else{
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let manager = managers?.first {
                    self.tunnel = manager
                    completion(Status(manager.connection.status))
                }else{
                    completion(.invalid)
                }
            }
        }
    }
    
    func sendMessage(msg:String){
        if let manager = tunnel {
            send(manager: manager,msg: msg)
        }else{
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let manager = managers?.first {
                    self.tunnel = manager
                    self.send(manager: manager,msg: msg)
                }
            }
        }
    }
    
    func send(manager:NETunnelProviderManager, msg:String){
        if let session = manager.connection as? NETunnelProviderSession {
            do {
                try session.sendProviderMessage(msg.data(using: .utf8)!) { rsp in
                    if let d = rsp {
                        print("\(String(data: d, encoding: .utf8) ?? "no message")")
                    }else{
                        print("进程通讯未收到响应")
                    }
                }
            } catch  {
                print("进程通讯失败")
            }
            
        }
    }
    
    func start(completion: @escaping Handler) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let manager = managers?.first {
                if !manager.isEnabled {
                    manager.isEnabled = true
                    manager.saveToPreferences { e in
                        self.start(completion: completion)
                    }
                }else{
                    self.tunnel = manager
                    do {
                        try self.tunnel!.connection.startVPNTunnel()
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
            }else{
                let manager = self.makeTunnelManager()
                manager.saveToPreferences { e in
                    self.start(completion: completion)
                }
            }
        }
    }

    func stop() {
        if let manager = tunnel {
            manager.connection.stopVPNTunnel()
        }else{
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let manager = managers?.first {
                    self.tunnel = manager
                    manager.connection.stopVPNTunnel()
                }
            }
        }
    }

    func removeFromPreferences(completion: @escaping Handler) {
        if let manager = tunnel {
            manager.removeFromPreferences { [weak self] error in
                self?.tunnel = nil
                completion(error)
            }
        }else{
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let manager = managers?.first {
                    self.tunnel = manager
                    manager.removeFromPreferences { [weak self] error in
                        self?.tunnel = nil
                        completion(error)
                    }
                }
            }
        }
    }
}

private extension NEManager {
    func makeTunnelManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "HTTP Packet Capture"
        manager.protocolConfiguration = {
            let configuration = NETunnelProviderProtocol()
            configuration.providerBundleIdentifier = NEManager.bundleIDTunnel
            configuration.serverAddress = "knot.sniffer"
            return configuration
        }()
        manager.isEnabled = true
        manager.isOnDemandEnabled = true
        return manager
    }
    
    @objc func vpnDidChange(noti:Notification) -> Void {
        guard let tunnelPS = noti.object as? NETunnelProviderSession else {
            print("Not NETunnelProviderSession !")
            return
        }
//        print("current vpn status : \(tunnelPS.status.rawValue)")
        statusDidChangeHandler?(Status(tunnelPS.status))
    }

}

public extension NEManager {
    enum Status: String {
        case on
        case off
        case invalid /// The VPN is not configured
        case connecting
        case disconnecting
        
        public init(_ status: NEVPNStatus) {
            switch status {
            case .connected:
                self = .on
            case .connecting, .reasserting:
                self = .connecting
            case .disconnecting:
                self = .disconnecting
            case .disconnected, .invalid:
                self = .off
            @unknown default:
                self = .off
            }
        }
    }
}
