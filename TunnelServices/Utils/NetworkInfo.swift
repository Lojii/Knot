//
//  NetworkInfo.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/4/30.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation

//- Requires: #include <ifaddrs.h> <sys/socket.h> <netinet/in.h>
public class NetworkInfo {
    enum Device: String {
        case LocalWifi = "en0"
        case Wan = "pdp_ip0"
    }
    
    enum Version { case iPv4, iPv6 }
    
    struct IPAddress {
        let device: String
        let IP: String
        let version: Version
        let mask: String
    }
    
    static func Cast<U, T>(ptr: UnsafeMutablePointer<U>) -> UnsafePointer<T>{
        let p_raw = UnsafeMutableRawPointer(ptr)
        let p_oq = OpaquePointer(p_raw)
        return UnsafePointer(p_oq)
    }
    
    
    static func IPAddressList() -> [IPAddress]? {
        var results = [IPAddress]()
        var ifa_list: UnsafeMutablePointer<ifaddrs>? = nil
        
        defer {
            if ifa_list != nil {
                freeifaddrs(ifa_list)
            }
        }
        
        guard getifaddrs(&ifa_list) == 0 else { return nil }
        
        var p_ifa = ifa_list
        while p_ifa != nil {
            
            let ifa = p_ifa?.pointee
            
            switch UInt8((ifa?.ifa_addr.pointee.sa_family)!) {
            case UInt8(AF_INET):    // IPv4
                let type = AF_INET
                let len = INET_ADDRSTRLEN
                
                guard let device = String(validatingUTF8: (ifa?.ifa_name)!) else { return nil }
                
                let addr_in_a:UnsafePointer<sockaddr_in> = Cast(ptr: (ifa?.ifa_addr)!)
                var socka = addr_in_a.pointee.sin_addr
                
                let addr_in_n:UnsafePointer<sockaddr_in> = Cast(ptr: (ifa?.ifa_netmask)!)
                var sockn = addr_in_n.pointee.sin_addr
                
                var addrstr = [CChar](repeating: 0, count: Int(len))
                inet_ntop(type, &socka, &addrstr, socklen_t(len))
                guard let IP = String(validatingUTF8: addrstr) else { return nil }
                
                var netmaskstr = [CChar](repeating: 0, count: Int(len))
                inet_ntop(type, &sockn, &netmaskstr, socklen_t(len))
                guard let mask = String(validatingUTF8: netmaskstr) else { return nil }
                
                results += [IPAddress(device: device, IP: IP, version: .iPv4, mask: mask)]
                
            case UInt8(AF_INET6):   // IPv6
                let type = AF_INET6
                let len = INET6_ADDRSTRLEN
                
                guard let device = String(validatingUTF8: (ifa?.ifa_name)!) else { return nil }
                
                let addr_in_a:UnsafePointer<sockaddr_in6> = Cast(ptr: (ifa?.ifa_addr)!)
                var socka = addr_in_a.pointee.sin6_addr
                
                let addr_in_n:UnsafePointer<sockaddr_in6> = Cast(ptr: (ifa?.ifa_netmask)!)
                var sockn = addr_in_n.pointee.sin6_addr
                
                var addrstr = [CChar](repeating: 0, count: Int(len))
                inet_ntop(type, &socka, &addrstr, socklen_t(len))
                guard let IP = String(validatingUTF8: addrstr) else { return nil }
                
                var netmaskstr = [CChar](repeating: 0, count: Int(len))
                inet_ntop(type, &sockn, &netmaskstr, socklen_t(len))
                guard let mask = String(validatingUTF8: netmaskstr) else { return nil }
                
                results += [IPAddress(device: device, IP: IP, version: .iPv6, mask: mask)]
                
            default: break
            }
            
            p_ifa = p_ifa?.pointee.ifa_next
        }
        
        return results
    }
    
    
    public static func LocalWifiIPv4() -> String {
        guard let list = IPAddressList() else { return "" }
        guard let i = list.firstIndex(where: { $0.device == Device.LocalWifi.rawValue && $0.version == .iPv4 }) else { return "" }
        return list[i].IP
    }
    
    public static func WanIPv4() -> String {
        guard let list = IPAddressList() else { return "" }
        guard let i = list.firstIndex(where: { $0.device == Device.Wan.rawValue && $0.version == .iPv4 }) else { return "" }
        return list[i].IP
    }
}
