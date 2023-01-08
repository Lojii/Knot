//
//  ManHelp.swift
//  NIOMan
//
//  Created by LiuJie on 2022/3/31.
//

import Foundation

// uri:POST http://amdc.m.taobao.com/amdc/mobileDispatch HTTP/1.1
// host:amdc.m.taobao.com

func findIPAndPort(host:String, uri:String) -> (host:String,port:String){
    var rp:String?
    var rh:String?
    // 先尝试从host字段里分离出地址和端口
    if host.split(separator: ":").count > 2 { // IPV6
        
    }else{
        let hostPs = host.components(separatedBy: ":")
        if hostPs.count == 2 { // 1.1.1.1:8080
            rp = hostPs[1]
            rh = hostPs[0]
        }
    }
    // 再尝试从uri里分离出地址和端口
    if rp == nil || rh == nil { // http://xxx.xx/xx
        if let urlP = uri.components(separatedBy: "://").last { // xxx.xx:xx/xx
            if let uriHostP = urlP.components(separatedBy: "/").first { // xxx.xx:xx
                let uhp = uriHostP.components(separatedBy: ":")
                if uhp.count == 2 {
                    rp = uhp[1]
                    rh = uhp[0]
                }
            }
        }
    }
    if rh == nil {
        rh = host
    }
    if rp == nil {
        rp = "80"
    }
    return (rh!,rp!)
}

func transitionStringToCChar(str:String) -> UnsafePointer<CChar>?{
    let char_str = str.cString(using: String.Encoding.utf8)!
    let unsafe_cchar = UnsafeMutablePointer<CChar>.allocate(capacity: char_str.count)
    unsafe_cchar.initialize(from: (char_str), count: char_str.count)
    return UnsafePointer<CChar>(unsafe_cchar)
}

@_silgen_name("findHost")
public func findHost(h: UnsafePointer<CChar>,u: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    let host = String(cString: h)
    let uri = String(cString: u)
    let res = findIPAndPort(host: host, uri: uri)
    return transitionStringToCChar(str: res.host)
}

@_silgen_name("findPort")
public func findPort(h: UnsafePointer<CChar>,u: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    let host = String(cString: h)
    let uri = String(cString: u)
    let res = findIPAndPort(host: host, uri: uri)
    return transitionStringToCChar(str: res.port)
}

