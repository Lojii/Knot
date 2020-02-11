//
//  RefreshUtil.swift
//  PullToRefreshKit
//
//  Created by huangwenchen on 16/7/12.
//  Copyright © 2016年 Leo. All rights reserved.
//

import Foundation
import UIKit

struct PullToRefreshKitConst{
    //KVO
    static let KPathOffSet = "contentOffset"
    static let KPathPanState = "state"
    static let KPathContentSize = "contentSize"
    
    //Default const
    static let defaultHeaderHeight: CGFloat = 50.0
    static let defaultFooterHeight: CGFloat = 44.0
    static let defaultLeftWidth: CGFloat    = 50.0
    static let defaultRightWidth: CGFloat   = 50.0
    
    //Tags
    static let headerTag = 100001
    static let footerTag = 100002
    static let leftTag   = 100003
    static let rightTag  = 100004
}

func PTRLocalize(_ string:String)->String{
    return NSLocalizedString(string, comment: "")
//    return NSLocalizedString(string, tableName: "Localize", bundle: Bundle(for: DefaultRefreshHeader.self), value: "", comment: "")
}

struct PullToRefreshKitHeaderString{
    static let pullDownToRefresh = PTRLocalize("pullDownToRefresh")
    static let releaseToRefresh = PTRLocalize("releaseToRefresh")
    static let refreshSuccess = PTRLocalize("refreshSuccess")
    static let refreshFailure = PTRLocalize("refreshFailure")
    static let refreshing = PTRLocalize("refreshing")
}

struct PullToRefreshKitFooterString{
    static let pullUpToRefresh = PTRLocalize("pullUpToRefresh")
    static let refreshing = PTRLocalize("refreshing")
    static let noMoreData = PTRLocalize("noMoreData")
    static let tapToRefresh = PTRLocalize("tapToRefresh")
    static let scrollAndTapToRefresh = PTRLocalize("scrollAndTapToRefresh")
}

struct PullToRefreshKitLeftString{
    static let scrollToClose = "滑动结束浏览"
    static let releaseToClose = "松开结束浏览"
}

struct PullToRefreshKitRightString{
    static let scrollToViewMore = "滑动浏览更多"
    static let releaseToViewMore = "滑动浏览更多"
}
