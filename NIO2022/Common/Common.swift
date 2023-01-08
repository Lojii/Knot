//
//  Common.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/24.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
import UIKit

let CONNECTEMAIL = "knotreport@gmail.com"

let SCREENWIDTH = UIScreen.main.bounds.width
let SCREENHEIGHT = UIScreen.main.bounds.height
var KScreenWidth = SCREENWIDTH
var KScreenHeight = SCREENHEIGHT
let STATUSBARHEIGHT = UIApplication.shared.statusBarFrame.height
var NAVGATIONBARHEIGHT:CGFloat = UIDevice.isX() ? 88:64
var XBOTTOMHEIGHT:CGFloat = UIDevice.isX() ? 34:0

var LRSpacing:CGFloat = 15

let ColorM = UIColor(hexString: "#3D7EFF")     // 蓝
let ColorR = UIColor(hexString: "#FF6666")     // 红
let ColorY = UIColor(hexString: "#F6E868")     // 黄
let ColorSG = UIColor(hexString: "#88D430")     // 绿状态
let ColorSR = UIColor(hexString: "#EB3524")     // 红状态
let ColorSY = UIColor(hexString: "#F8B22F")     // 黄状态
let ColorSH = UIColor(hexString: "#AEAEAE")     // 灰状态
let ColorA = UIColor(hexString: "#303133")     // 一级信息、标题、主内容文字等
let ColorB = UIColor(hexString: "#606266")     // 普通级别文字、正文内容文字等
let ColorC = UIColor(hexString: "#909399")     // 辅助文字、次要信息等
let ColorD = UIColor(hexString: "#BFC2CC")     // 小段描述文字、次要文字、输入框提示文字等
let ColorE = UIColor(hexString: "#EDEFF2")     // 分割线、按钮边框、置灰按钮背景等
let ColorF = UIColor(hexString: "#F5F7FA")     // 页面最底层背景等

let Font10 = UIFont.systemFont(ofSize: 10)
let Font11 = UIFont.systemFont(ofSize: 11)
let FontC10 = UIFont(name: "Courier", size: 10) // Courier New
let FontC11 = UIFont(name: "Courier", size: 11) // Courier New
let Font12 = UIFont.systemFont(ofSize: 12)
let Font13 = UIFont.systemFont(ofSize: 13)
let Font14 = UIFont.systemFont(ofSize: 14)
let Font16 = UIFont.systemFont(ofSize: 16)
let Font18 = UIFont.systemFont(ofSize: 18)
let Font24 = UIFont.systemFont(ofSize: 24)




var dialogWidth: CGFloat = 300

var RGBAColor: (CGFloat, CGFloat, CGFloat, CGFloat) -> UIColor = {red, green, blue, alpha in
    return UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha);
}

// MARK:- 设置圆角
func HDViewsBorder(_ view:UIView, borderWidth:CGFloat, borderColor:UIColor?=nil,cornerRadius:CGFloat){
    view.layer.borderWidth = borderWidth;
    view.layer.borderColor = borderColor?.cgColor
    view.layer.cornerRadius = cornerRadius
    view.layer.masksToBounds = true
}

let HDWindow = UIApplication.shared.keyWindow
let HDNotificationCenter = NotificationCenter.default
let HDUserDefaults = UserDefaults.standard

public class IDealistConfig: NSObject {
    
    public static let share = IDealistConfig()
    
    // loading展示时间最长为60秒
    public var maxShowInterval: Float = 60
    
    /// switch主题色、progressView主题色、
    public var mainColor: UIColor = UIColor.init(red: 13/255.0, green: 133/255.0, blue: 255/255.0, alpha: 1)
    
    public func id_setupMainColor(color: UIColor) {
        self.mainColor = color
    }
}
