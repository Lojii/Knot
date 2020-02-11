//
//  GiFHUD.swift
//  Loadding
//
//  Created by darren on 2017/11/27.
//  Copyright © 2017年 陈亮陈亮. All rights reserved.
// 默认展示可以与用户交互的视图
// 支持3种类型

import UIKit

public class IDLoading: NSObject {
    
    static var gifUtil: IDLoadingGifUtil?
    static var freeUtil: IDLoadingFreeUtil?
    static var waitUtil: IDLoadingWaitUtil?
    static var navUtil: IDLoadingNavUtil?
    
    // 默认展示不会阻止用户交互的控件
    public static func id_show(onView: UIView? = nil) {
        if self.freeUtil != nil {
            self.id_dismiss()
        }
        self.freeUtil = IDLoadingFreeUtil.init(onView: onView)
    }
    // 展示阻止用户交互的控件
    public static func id_showWithWait(onView: UIView? = nil) {
        if self.waitUtil != nil {
            self.id_dismissWait()
        }
        self.waitUtil = IDLoadingWaitUtil.init(onView: onView)
    }
    
    // 展示进度条
    public static func id_showProgressLine(onView: UIView, colors: [CGColor]? = nil) {
        if self.navUtil != nil {
            self.id_dismissNav()
        }
        self.navUtil = IDLoadingNavUtil(onView: onView, colors: colors)
    }
    
    // 展示自定义的gif图
    public static func id_showGif(gifName: String? = nil,type: IDLoadingUtilLoadingType? = nil, onView: UIView? = nil) {
        if self.gifUtil != nil {
            self.id_dismissGif()
        }
        self.gifUtil = IDLoadingGifUtil.init(gifName: gifName,type: type,  onView: onView)
    }

    // 对应id_show
    public static func id_dismiss() {
        self.freeUtil?.dismiss()
        self.freeUtil = nil
    }
    // 对应id_showGif
    public static func id_dismissGif() {
        self.gifUtil?.dismiss()
        self.gifUtil = nil
    }
    // 对应id_showWithOverlay
    public static func id_dismissWait() {
        self.waitUtil?.dismiss()
        self.waitUtil = nil
    }
    
    public static func id_dismissNav() {
        self.navUtil?.dismiss()
        self.navUtil = nil
    }
    
}


