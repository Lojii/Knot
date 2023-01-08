//
//  Dictionary+Extension.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/5/2.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation

extension Dictionary{
    public func toJson() -> String{
        if (!JSONSerialization.isValidJSONObject(self)) {
            print("无法解析出JSONString")
            return ""
        }
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: []) else {
            print("无法解析出JSONString")
            return ""
        }
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        return jsonString
    }
    
    
    public static func fromJson(_ json:String) -> Dictionary{
        let jsonData:Data = json.data(using: .utf8)!
        let dict = try? JSONSerialization.jsonObject(with: jsonData, options: .mutableContainers)
        if dict != nil {
            return dict as! Dictionary
        }
        return Dictionary()
    }
}
