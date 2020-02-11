//
//  GeneralItem.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

public class GeneralItem: RuleLine {
    
    public var key:String = ""
    public var value:String = ""
    public var annotation:String?  // 注释
    
    static func == (lhs: GeneralItem, rhs: GeneralItem) -> Bool {
        return lhs.key == rhs.key
    }
    
    override func lineWillGet() {
        if annotation != nil, annotation != "" {
            _line = "\(key) = \(value) // \(annotation!)"
        }else{
            _line = "\(key) = \(value)"
        }
    }

    public static func fromLine(_ line:String, success:((GeneralItem) -> Void), failure:((String?) -> Void) ) -> Void {
        if line == "" {
            failure(nil)
            return
        }
        
        let item = GeneralItem()
        item.lineType = .General
        var parts = line.components(separatedBy: "//")
        // 有效部分
        let payload = parts[0]
        if payload.trimmingCharacters(in: .whitespaces) == "" {
            failure(nil)
            return
        }
        // 注释
        parts.removeFirst()
        let annotation = parts.joined(separator: "//")
        item.annotation = annotation
        // 解析有效部分
        var generalParts = payload.components(separatedBy: "=")
        if generalParts.count == 0 {
            failure(nil)
            return
        }
        item.key = generalParts[0].trimmingCharacters(in: .whitespaces).lowercased()
        if generalParts.count >= 2 {
            generalParts.removeFirst()
            if generalParts.first == "" {
                failure(nil)
                return
            }
            item.value = generalParts.joined(separator: "=").trimmingCharacters(in: .whitespaces)
        }
        success(item)
    }
}
