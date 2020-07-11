//
//  IDSegmentedControl.swift
//  IDUIKit-ios
//
//  Created by darren on 2018/12/5.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit



public class IDSegmentedView: UISegmentedControl {
    
    public func id_setSegmentStyle(textColor: UIColor, selectedColor: UIColor, textFont: UIFont) {
        let selectedColorImage = UIImage.renderImageWithColor(selectedColor, size: CGSize(width: 1.0, height: 1.0))
        setBackgroundImage(selectedColorImage, for: .selected, barMetrics: .default)
        
        let segAttributesNormal = [NSAttributedString.Key.foregroundColor: textColor, NSAttributedString.Key.font: textFont]
        let segAttributesSeleted = [NSAttributedString.Key.foregroundColor: UIColor.black,NSAttributedString.Key.font: textFont]
        // 文字在两种状态下的颜色
        setTitleTextAttributes(segAttributesNormal, for: UIControl.State.normal)
        setTitleTextAttributes((segAttributesSeleted), for: UIControl.State.selected)
        
        // 边界颜色、圆角
//        self.layer.borderWidth = 0.7
//        self.layer.cornerRadius = 5.0
//        self.layer.borderColor = dividerColor.cgColor
//        self.layer.masksToBounds = true
    }
}

fileprivate extension UIImage{
    
    /// 通过颜色生成图片
//    class func renderImageWithColor(_ color: UIColor, size: CGSize) -> UIImage {
//        UIGraphicsBeginImageContext(size)
//        guard let context = UIGraphicsGetCurrentContext() else {
//            UIGraphicsEndImageContext()
//            return UIImage()
//        }
//        context.setFillColor(color.cgColor);
//        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height));
//        let img = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        return img ?? UIImage()
//    }
}

