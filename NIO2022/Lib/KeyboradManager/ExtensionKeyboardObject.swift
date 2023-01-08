//
//  WHC_ExtensionObject.swift
//  WHC_KeyboardManager
//
//  Created by WHC on 16/11/15.
//  Copyright © 2016年 WHC. All rights reserved.
//

//  Github <https://github.com/netyouli/WHC_KeyboardManager>

//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit

public extension NSObject {
    
    /// 获取app当前显示的控制器
    ///
    /// - returns: app当前显示的控制器
    func currentViewController() -> UIViewController? {
        var currentViewController: UIViewController!
        let window = UIApplication.shared.keyWindow
        currentViewController = window?.rootViewController
        return scanCurrentController(currentViewController)
    }
    
    
    /// 扫描获取最前面的控制器
    ///
    /// - parameter viewController: 要扫描的控制器
    ///
    /// - returns: 返回最上面的控制器
    private func scanCurrentController(_ viewController: UIViewController?) -> UIViewController? {
        var currentViewController: UIViewController?
        if viewController != nil {
            if viewController is UINavigationController && (viewController as! UINavigationController).topViewController != nil {
                currentViewController = (viewController as! UINavigationController).topViewController
                currentViewController = scanCurrentController(currentViewController)
            }else if viewController is UITabBarController && (viewController as! UITabBarController).selectedViewController != nil {
                currentViewController = (viewController as! UITabBarController).selectedViewController
                currentViewController = scanCurrentController(currentViewController)
            }else {
                currentViewController = viewController
                var hasPresentController = false
                while let presentedController = currentViewController?.presentedViewController {
                    hasPresentController = true
                    currentViewController = presentedController
                }
                if hasPresentController {
                    currentViewController = scanCurrentController(currentViewController)
                }
            }
        }
        return currentViewController
    }
}
