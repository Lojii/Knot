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
