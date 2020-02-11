//
//  ZKProgressHUDAnimationShowStyle.swift
//  ZKProgressHUD
//
//  Created by 王文壮 on 2017/4/25.
//  Copyright © 2017年 WangWenzhuang. All rights reserved.
//

import UIKit

/// 加载动画样式
public enum ZKProgressHUDAnimationShowStyle {
    /// 淡入/淡出（默认）
    case fade
    /// 缩放
    case zoom
    /// 飞入
    case flyInto
}
typealias AnimationShowStyle = ZKProgressHUDAnimationShowStyle
