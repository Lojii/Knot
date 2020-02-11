//
//  UILabel+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/11.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
import UIKit

extension UILabel{
    static func initWith(color:UIColor = .black,font:UIFont = UIFont.systemFont(ofSize: 14),text:String = "",frame:CGRect = CGRect.zero) -> UILabel{
        let label = UILabel(frame: frame)
        label.text = text
        label.textColor = color
        label.font = font
        return label
    }
}
