//
//  Config.swift
//  IDLoading
//
//  Created by darren on 2018/11/23.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit
public enum IDLoadingUtilLoadingType {
    case wait  // 会阻止用户交互， 需要等待加载完成
    case nav // 一条进度线条
    case free // 不会阻止用户交互
}
