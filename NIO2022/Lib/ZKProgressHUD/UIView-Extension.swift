//
//  UIView-Extension.swift
//  ZKProgressHUD
//
//  Created by 王文壮 on 2017/4/19.
//  Copyright © 2017年 WangWenzhuang. All rights reserved.
//

import UIKit

/// UIView，便捷获取 frame 值
extension UIView {
    var width: CGFloat {
        return self.frame.size.width
    }
    var height: CGFloat {
        return self.frame.size.height
    }
    var x: CGFloat {
        return self.frame.origin.x
    }
    var y: CGFloat {
        return self.frame.origin.y
    }
}
