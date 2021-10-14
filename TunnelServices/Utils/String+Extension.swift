//
//  String+Extension.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/5/4.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

public extension String{
    
    func isNumber() -> Bool {
//        return NSPredicate(format: "SELF MATCHES ^[0-9]+$").evaluate(with: self)
        let pattern = "^[0-9]+$"
        if NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: self) {
            return true
        }
        return false
    }
    
    func getRealType() -> String {
        if let t = self.components(separatedBy: ";").first {
            if let realType = t.components(separatedBy: "/").last {
                if realType.lowercased() == "text" {
                    return "txt"
                }
                if realType.lowercased() == "javascript" {
                    return "js"
                }
                return realType
            }
        }
        return ""
    }
    
    func getFileName() -> String {
        let uriParts = self.components(separatedBy: "?")
        if let fpart = uriParts.first {
            let paths = fpart.components(separatedBy: "/")
            if let lastPath = paths.last{
                return lastPath
            }
        }
        return ""
    }
    
    func isIPAddress() -> Bool {
        // We need some scratch space to let inet_pton write into.
        var ipv4Addr = in_addr()
        var ipv6Addr = in6_addr()

        return self.withCString { ptr in
            return inet_pton(AF_INET, ptr, &ipv4Addr) == 1 ||
                   inet_pton(AF_INET6, ptr, &ipv6Addr) == 1
        }
    }
    
//    /// URL编码
//    func urlEncoded() -> String {
//        let characterSet = CharacterSet(charactersIn: ":/?#[]@!$ &'()*+,;=\"<>%{}|\\^~`")
//        return self.addingPercentEncoding(withAllowedCharacters: characterSet)!
//    }
//    /// URL解码
//    func urlDecode() -> String? {
//        return self.removingPercentEncoding
//    }
}
