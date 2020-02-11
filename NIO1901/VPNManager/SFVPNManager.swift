//
//  SFVPNManager.swift
//  Surf
//
//  Created by yarshure on 16/2/5.
//  Copyright © 2016年 yarshure. All rights reserved.
//

import Foundation
import NetworkExtension
import TunnelServices

extension NEVPNStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .invalid: return "Invalid"
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnecting: return "Disconnecting"
        case .reasserting: return "Reconnecting"
        @unknown default:
            fatalError()
        }
    }
    public var titleForButton:String {
        switch self{
        case .disconnected:
            return "Connect"
        case .invalid:
            return "Invalid"
        case .connected:
            return "Disconnect"
        case .connecting:
            return "Connecting"
        case .disconnecting:
            return "Disconnecting"
        case .reasserting:
            return "Reasserting"
        @unknown default:
            fatalError()
        }
    }
}

class SFNETunnelProviderManager:NETunnelProviderManager {
    class func loadOrCreateDefaultWithCompletionHandler(_ completionHandler: ((NETunnelProviderManager?, Error?) -> Void)?) {
//        print("***************SFVPNManager loadOrCreateDefaultWithCompletionHandler") // **
        self.loadAllFromPreferences { (managers, error) -> Void in
            if let error = error {
                print("Error: Could not load managers:  \(error.localizedDescription)")
                if let completionHandler = completionHandler {
                    completionHandler(nil, error)
                }
                return
            }
            let bId = Bundle.main.infoDictionary!["CFBundleIdentifier"] as! String
            if let managers = managers {
                if managers.indices ~= 0 {
                    if let completionHandler = completionHandler {
                        var m:NETunnelProviderManager?
                        for mm in managers {
                            let _ = mm.protocolConfiguration as! NETunnelProviderProtocol
                        }
                        if m == nil {
                            m = managers[0]
                        }
//                        print("manager \(managers.count) \(String(describing: m?.protocolConfiguration))")
                        completionHandler(m, nil)
                    }
                    return
                }
            }
            
            var configInfo = [String:Any]()
            configInfo["App"] = bId
//            configInfo["PluginType"] = "Lojii.NIO1901"
//            configInfo["port"] = 8034
//            configInfo["server"] = "127.0.0.1:8034"
//            configInfo["ip"] = "10.8.0.2"
//            configInfo["subnet"] = "255.255.255.0"
            configInfo["mtu"] = "1400"
            configInfo["dns"] = "8.8.8.8,8.4.4.4"
            
            let config = NETunnelProviderProtocol()
            config.providerConfiguration = configInfo
            config.providerBundleIdentifier = "Lojii.NIO1901.PacketTunnel"
            config.serverAddress = "Knot.Local"//"240.84.1.24"
            
            let manager = SFNETunnelProviderManager()
            manager.protocolConfiguration = config
            manager.localizedDescription = "HTTP Packet Capture".localized
            
            manager.saveToPreferences(completionHandler: { (error) -> Void in
                if let completionHandler = completionHandler {
                    completionHandler(manager, error)
                }
            })
        }
    }
}

class SFVPNManager {
    static let shared:SFVPNManager =  SFVPNManager()
    var manager:NETunnelProviderManager?
    var loading:Bool = false
    var session:String = ""
    var vpnmanager:NEVPNManager = NEVPNManager.shared()
    
    func loadManager(_ completionHandler: ((NETunnelProviderManager?, Error?) -> Void)?) {
//        print("***************SFVPNManager loadManager")  // ***
        if let m = manager {
            if let handler = completionHandler{
                handler(m, nil)
            }
        }else {
            loading = true
            SFNETunnelProviderManager.loadOrCreateDefaultWithCompletionHandler { [weak self] (manager, error) -> Void in
                if let m = manager {
                    self!.manager = manager
                    if let handler = completionHandler{
                        self!.loading = false
                        handler(m, error)
                    }
                }
            }
        }
    }
    
    func enabledToggled(_ start:Bool) {
//        print("***************SFVPNManager enabledToggled") // **
        if let m = manager {
            m.isEnabled = true
            m.localizedDescription = "HTTP Packet Capture".localized
            m.saveToPreferences {  error in
//                guard error == nil else {
//                    print("saveToPreferences error:\(error?.localizedDescription ?? "unknow")")
//                    return
//                }
                m.loadFromPreferences { error in
//                    print("loadFromPreferencesWithCompletionHandler \(String(describing: error?.localizedDescription))")
                    if start {
                        do {
                            _ = try self.startStopToggled()
                        }catch let error {
                            print(error)
                        }
                    }
                    
                }
                
            }
        }
    }
    
    /// Handle the user toggling the "VPN" switch.
    func startStopToggled() throws -> Bool{
        print("***************SFVPNManager startStopToggled")// ***
        if let m = manager {
            if m.connection.status == .disconnected || m.connection.status == .invalid {
                do {
                    if  m.isEnabled {
                        print("starting!!!")
                        try m.connection.startVPNTunnel()
                    }else {
                        enabledToggled(true)
                    }
                }
                catch let error  {
                    print("Failed to start the VPN: \(error)")
                    throw error
                }
            }
            else {
                print("stoping!!!")
                m.connection.stopVPNTunnel()
            }
        }else {
            return false
        }
        return true
    }
}
