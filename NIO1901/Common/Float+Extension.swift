//
//  Float+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/12.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation

extension Float {
    func bytesFormatting() -> String {
        let units = ["B","KB","MB","GB","TB","PB", "EB", "ZB", "YB", nil]
        var b = self
        var index = 0
        while b > 1024 {
            b = b / 1024
            index = index + 1
        }
        if index <= units.count {
            if index == 0 {
                return "\(Int(b)) \(units[index] ?? "")"
            }
            return "\(String(format: "%.2f", b)) \(units[index] ?? "")"
        }
        return ""
    }
}
