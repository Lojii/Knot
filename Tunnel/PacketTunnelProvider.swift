//
//  PacketTunnelProvider.swift
//  Tunnel
//
//  Created by LiuJie on 2022/3/20.
//

import NetworkExtension
import os.log
import NIOMan

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var pendingCompletion: ((Error?) -> Void)?
    open var connection: NWTCPConnection!
    
    private var udpSession: NWUDPSession!
    private var observer: AnyObject?
    private lazy var dataStorage = UserDefaults(suiteName: NEManager.groupID)!
    
    private var proxyAutoConfigurationJavaScript:String = ""
    
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        DispatchQueue.global().async{
            if #available(iOSApplicationExtension 12.0, *) { os_log(.default, log: .default, "NIOMan.run") }
            let time = Date().timeIntervalSince1970
            let taskId = String(format: "%.0f", time)
            let gud = UserDefaults(suiteName: GROUPNAME)
            gud?.set(taskId, forKey: CURRENTTASKID)
            gud?.synchronize()
            let res = NIOMan.run(taskId: taskId)
            if res == 0 {
                gud?.removeObject(forKey: CURRENTTASKID)
                gud?.synchronize()
            }
        }
        
        let endpoint = NWHostEndpoint(hostname:NIOManConfig.host, port:NIOManConfig.port)
        self.connection = self.createTCPConnection(to: endpoint, enableTLS:false, tlsParameters:nil, delegate:nil)
        pendingCompletion = completionHandler
        
        setTunnelNetworkSetting {[weak self] e in
            self?.pendingCompletion!(nil)
        }

    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        print("PacketTunnelProvider stopTunnel !")
        NIOMan.stop()
        if #available(iOSApplicationExtension 12.0, *) { os_log(.default, log: .default, "PacketTunnelProvider stopTunnel !") }
        // Add code here to start the process of stopping the tunnel.
        completionHandler()
    }
    
    /// 处理主App发送过来的消息，
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let str = String(data: messageData, encoding: .utf8) {
            if ConfigDidChangeAppMessage == str {
                setTunnelNetworkSetting { [weak self] error in
                    if let handler = completionHandler {
                        handler(self?.proxyAutoConfigurationJavaScript.data(using: .utf8))
                    }
                }
                return
            }
        }
        if let handler = completionHandler {
            handler(messageData)
        }
    }
    
    func setTunnelNetworkSetting(completionHandler:@escaping (Error?) -> Void){
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1500
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"])
        settings.ipv4Settings = {
            let settings = NEIPv4Settings(addresses: ["127.0.0.1"], subnetMasks: ["255.255.255.255"])
//            let settings = NEIPv4Settings(addresses: ["10.0.0.1"], subnetMasks: ["255.0.0.0"])
//            settings.includedRoutes = [NEIPv4Route.default()]
//            settings.excludedRoutes = [
//                NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
//                NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
//                NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0")
//            ]
            return settings
        }()
//        settings.ipv6Settings = {
//            let ipv6 = NEIPv6Settings(addresses: ["::ffff:a00:1"], networkPrefixLengths: [96])
//            let r1 = NEIPv6Route(destinationAddress: "::", networkPrefixLength: 1)
//            let r2 = NEIPv6Route(destinationAddress: "8000::", networkPrefixLength: 1)
//            ipv6.includedRoutes = [r1,r2]
//            return ipv6
//        }()
        
        let proxy = "\(NIOManConfig.host):\(NIOManConfig.port)"
        let currentRule = Rule.currentRule()
        let pacJS = currentRule.pacJS(proxy: proxy)
//        if let rid = UserDefaults(suiteName: GROUPNAME)?.string(forKey: CURRENTRULEID),let iid = NumberFormatter().number(from: rid){
//            if let cr = Rule.find(id: iid) {
//                pacJS = cr.pacJS(proxy: proxy)
//            }
//        }
        proxyAutoConfigurationJavaScript = pacJS
        if #available(iOSApplicationExtension 14.0, *) {
            os_log(.default, log: .default, "\(pacJS)")
        } else {
            
        }
        settings.proxySettings = {
            let settings = NEProxySettings()
//            settings.matchDomains = ["www.baidu.com","cn.bing.com","api.asilu.com","www.apple.com","1.1.1.1"]
            settings.matchDomains = [""]
            settings.exceptionList = [ "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "127.0.0.1", "localhost", "*.local" ]
            settings.autoProxyConfigurationEnabled = true
            settings.proxyAutoConfigurationJavaScript = pacJS
            return settings
        }()
        
        setTunnelNetworkSettings(settings) {/*[weak self]*/ e in
            if((e) == nil){
//                self?.readPackets()
                completionHandler(nil)
            }else{
                if #available(iOSApplicationExtension 12.0, *) { os_log(.default, log: .default, "setTunnelNetworkSettings error: %{public}@", "\(e.debugDescription)") }
                completionHandler(e)
            }
        }
    }
    
    /// 当设备即将进入睡眠状态时，系统会调用此方法。
    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }
    
    /// 当设备从睡眠模式唤醒时，系统会调用此方法。
    override func wake() {
        // Add code here to wake up.
    }
    
    func readPackets() -> Void {
        packetFlow.readPackets {[weak self] (packets, protocols) in
            guard let strongSelf = self else { return }
            for packet in packets {
                strongSelf.connection.write(packet, completionHandler: { (error) in
                })
            }
            // Repeat
            strongSelf.readPackets()
        }
    }
}
