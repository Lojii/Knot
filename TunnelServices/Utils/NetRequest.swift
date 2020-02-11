//
//  NetRequest.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/20.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
import NIOHTTP1

class NetRequest {
    
    public var host:String = ""
    public var port:Int = -1
    public var ssl:Bool = false
    public var head:HTTPRequestHead
    
    init(_ head: HTTPRequestHead) {
        self.head = head
        
        if head.uri.contains("https://") {
            ssl = true
        }
        // 先从headers里提取Host，如果没有，则从uri中提取
        host = head.headers["Host"].first ?? ""
        let hostArray:[String] = host.split(separator: ":").compactMap { "\($0)" }
        if hostArray.count > 1 {
            let p = hostArray[1]
            if p.isNumber() {
                port = Int(p) ?? -1
            }
            host = hostArray[0]
        }
        
        if host == "" {
            if head.uri.contains("://"),let url = URL(string: head.uri) {
                host = url.host ?? ""
            }else{
                let arrayStrings: [String] = head.uri.split(separator: ":").compactMap { "\($0)" }
                if arrayStrings.count == 2 || arrayStrings.count == 3{
                    host = arrayStrings[arrayStrings.count - 2]
                }else if arrayStrings.count == 1{
                    host = arrayStrings[0]
                }else{
                    host = ""
                }
            }
        }
        if port == -1 {
            if head.uri.contains("://"),let url = URL(string: head.uri) {
                port = url.port ?? -1
            }else{
                let arrayStrings: [String] = head.uri.split(separator: ":").compactMap { "\($0)" }
                if arrayStrings.count >= 2{
                    port = Int(arrayStrings.last!) ?? -1
                }else{
                    port = -1
                }
            }
        }
        if port == -1 {
            port = ssl ? 443 : 80
        }
    }
    
    public static func removeProxyHead(heads:HTTPHeaders) -> HTTPHeaders{
        var h = heads
        h.remove(name: "Proxy-Authenticate")
        h.remove(name: "Proxy-Connection")
        h.remove(name: "Expect")
        return h
    }
    

}
