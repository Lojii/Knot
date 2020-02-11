//
//  Date+Extension.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/6/11.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

extension Date {
    ///获取当前时间字符串
    public var fullSting:String{
        let dateFormatter = DateFormatter.init()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
        let dataString = dateFormatter.string(from: self)
        return dataString
    }
}
