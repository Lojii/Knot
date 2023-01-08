//
//  IDDialog.swift
//  IDDialog
//
//  Created by darren on 2018/8/29.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit
public class IDDialog: NSObject {
    /// 普通弹框
    public static func id_show(
                               title: String? = nil,
                               msg: String? = nil,
                               countDownNumber: Int? = nil,
                               leftActionTitle: String?,
                               rightActionTitle: String?,
                               leftHandler: (()->())? = nil,
                               rightHandler:(()->())? = nil) {
        _ = IDDialogUtil.init(title: title, msg: msg, leftActionTitle: leftActionTitle, rightActionTitle: rightActionTitle, leftHandler: leftHandler, rightHandler: rightHandler,countDownNumber: countDownNumber,type: IDDialogUtilType.normal)
    }
    /// 带图片
    public static func id_showImg(
                               success: IDDialogUtilImageType? = nil,
                               msg: String? = nil,
                               leftActionTitle: String?,
                               rightActionTitle: String?,
                               leftHandler: (()->())? = nil,
                               rightHandler:(()->())? = nil) {
        _ = IDDialogUtil.init(msg: msg, leftActionTitle: leftActionTitle, rightActionTitle: rightActionTitle, leftHandler: leftHandler, rightHandler: rightHandler,success: success,type: IDDialogUtilType.image)
    }
    
    public static func id_showInput(
                                  msg: String? = nil,
                                  leftActionTitle: String?,
                                  rightActionTitle: String?,
                                  leftHandler: ((String)->())? = nil,
                                  rightHandler:((String)->())? = nil) {
        _ = IDDialogUtil.init(msg: msg, leftActionTitle: leftActionTitle, rightActionTitle: rightActionTitle, leftHandler: leftHandler, rightHandler: rightHandler, type: IDDialogUtilType.input)
    }
    
    /// 自定义内容
    public static func id_showCustom(
        msg: String? = nil,
        leftActionTitle: String?,
        rightActionTitle: String?,
        customView: UIView?,
        leftHandler: ((UIView?)->())? = nil,
        rightHandler:((UIView?)->())? = nil) {
        _ = IDDialogUtil.init(msg: msg, leftActionTitle: leftActionTitle, rightActionTitle: rightActionTitle,customView: customView, leftHandler: leftHandler, rightHandler: rightHandler, type: IDDialogUtilType.custom)
    }
}
