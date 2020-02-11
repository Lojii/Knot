//
//  String-Extension.swift
//  ZKProgressHUD
//
//  Created by 王文壮 on 2017/4/20.
//  Copyright © 2017年 WangWenzhuang. All rights reserved.
//

import UIKit

/// String，获取字符串尺寸
extension String {
    func size(font: UIFont, size: CGSize) -> CGSize {
        let attribute = [ NSAttributedString.Key.font: font ]
        let conten = NSString(string: self)
        return conten.boundingRect(with: CGSize(width: size.width, height: size.height), options: .usesLineFragmentOrigin, attributes: attribute, context: nil).size
    }
}
