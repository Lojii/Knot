//
//  VPNTunnelManager.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/5/1.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
import NetworkExtension

public class VPNTunnelManager: NSObject {
    
    public var vpnManager: NETunnelProviderManager!
    
    public override init() {
        super.init()
        self.vpnManager = NETunnelProviderManager()
        self.applyVpnConfiguration()
    }
    
    public func startVPN() -> Bool{
        if vpnManager.connection.status == .disconnected{
            do{
                try vpnManager.connection.startVPNTunnel()
                print("Start VPN Success !")
                return true
            }catch{
                print("Start VPN Failed !",error.localizedDescription)
                return false
            }
        }else{
            print("Start VPN - The current connect status isn't NEVPNStatusDisconnected !")
        }
        return false
    }
    
    public func stopVPN() -> Bool{
        if vpnManager.connection.status == .connected {
            vpnManager.connection.stopVPNTunnel()
            print("StopVPN Success - The current connect status is Connected.")
            return true
        }else if vpnManager.connection.status == .connecting{
            vpnManager.connection.stopVPNTunnel()
            print("StopVPN Success - The current connect status is Connecting.")
            return true
        }else{
            print("StopVPN Failed - The current connect status isn't Connected or Connecting !")
        }
        return false
    }
    
    func applyVpnConfiguration() -> Void {
        NETunnelProviderManager.loadAllFromPreferences { (tunnelProviderManagers, error) in
            guard let managers = tunnelProviderManagers else {
                print("The vpn config is NULL, we will config it later.")
                self.loadFromPreferences()
                return
            }
            if managers.count > 0 {
                self.vpnManager = managers[0]
                print("The vpn already configured. We will use it.")
                return
            }else{
                print("The vpn config is NULL, we will config it later.")
            }
            self.loadFromPreferences()
        }
    }
    
    func loadFromPreferences() -> Void {
        vpnManager.loadFromPreferences { (error) in
            if error != nil{
                print("applyVpnConfiguration loadFromPreferencesWithCompletionHandler Failed !",error!.localizedDescription)
                return
            }
            
            var configInfo = [String:Any]()
            configInfo["port"] = 8034
            configInfo["server"] = "127.0.0.1:8034"
            configInfo["ip"] = "10.8.0.2"
            configInfo["subnet"] = "255.255.255.0"
            configInfo["mtu"] = "1400"
            configInfo["dns"] = "8.8.8.8,8.4.4.4"
            
            let tunnelProviderProtocol = NETunnelProviderProtocol()
            tunnelProviderProtocol.providerBundleIdentifier = "Lojii.NIO1901.PacketTunnel"
            tunnelProviderProtocol.providerConfiguration = configInfo
            tunnelProviderProtocol.serverAddress = "127.0.0.1:8034"
            
            self.vpnManager.protocolConfiguration = tunnelProviderProtocol
            self.vpnManager.localizedDescription = "NIO VPN"
            self.vpnManager.isEnabled = true
            self.vpnManager.saveToPreferences(completionHandler: { (error) in
                if (error != nil) {
                    print("applyVpnConfiguration saveToPreferencesWithCompletionHandler Failed !",error!.localizedDescription)
                }else {
                    self.applyVpnConfiguration()
                    print("Save vpn configuration successfully !")
                }
            })
        }
    }
}
