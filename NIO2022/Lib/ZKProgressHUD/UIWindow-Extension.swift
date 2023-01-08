//
//  UIWindow-Extension.swift
//  Demo
//
//  Created by 王文壮 on 2019/3/25.
//  Copyright © 2019 WangWenzhuang. All rights reserved.
//

import UIKit

extension UIWindow {
    static var frontWindow: UIWindow? {
        return UIApplication.shared.windows.reversed().first(where: {
            $0.screen == UIScreen.main &&
                !$0.isHidden && $0.alpha > 0 &&
                $0.windowLevel == UIWindow.Level.normal
        })
    }
}
