//
//  UIDevice+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/28.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
public extension UIDevice {
    /// iPhone X 在竖屏下，keyWindow 的 safeAreaInsets 值为：{top: 44, left: 0, bottom: 34, right: 0}
    /// 而在横屏下，其值为：{top: 0, left: 44, bottom: 21, right: 44}
    static func isX() -> Bool {
        let window = UIApplication.shared.keyWindow
        if #available(iOS 11.0, *) {
            let bottomSafeInset = window?.safeAreaInsets.bottom
            if (bottomSafeInset == 34.0 || bottomSafeInset == 21.0) {
                return true
            } else {
                if (UIScreen.main.bounds.height > 800) {
                    return true
                } else {
                    return false
                }
            }
        } else {
            if (UIScreen.main.bounds.height > 800) {
                return true
            } else {
                return false
            }
        }
    }
    
    static func isIOS11() -> Bool {
        if #available(iOS 11.0, *) {
            return true
        } else {
            return false
        }
    }
}
