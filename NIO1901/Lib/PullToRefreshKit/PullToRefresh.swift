//
//  PullToRefreshKit.swift
//  PullToRefreshKit
//
//  Created by huangwenchen on 16/7/11.
//  I refer a lot logic for MJRefresh https://github.com/CoderMJLee/MJRefresh ,thanks to this lib and all contributors.
//  Copyright © 2016年 Leo. All rights reserved.

import Foundation
import UIKit
import ObjectiveC

// MARK: - Header API  -

@objc class AttachObject:NSObject{
    init(closure:@escaping ()->()) {
        onDeinit = closure
        super.init()
    }
    var onDeinit:()->()
    deinit {
        onDeinit()
    }
}

@objc public enum RefreshResult:Int{
    case success = 200
    case failure = 400
    case none = 0
}

public enum HeaderRefresherState {
    case refreshing //刷新中
    case normal(RefreshResult,TimeInterval)//正常状态
    case removed //移除
}

public extension UIScrollView{
    func invalidateRefreshControls(){
        let tags = [PullToRefreshKitConst.headerTag,
                    PullToRefreshKitConst.footerTag,
                    PullToRefreshKitConst.leftTag,
                    PullToRefreshKitConst.rightTag]
        tags.forEach { (tag) in
            let oldContain = self.viewWithTag(tag)
            oldContain?.removeFromSuperview()
        }
    }
    func configAssociatedObject(object:AnyObject){
        guard objc_getAssociatedObject(object, &AssociatedObject.key) == nil else{
            return;
        }
        let attach = AttachObject { [weak self] in
            self?.invalidateRefreshControls()
        }
        objc_setAssociatedObject(object, &AssociatedObject.key, attach, .OBJC_ASSOCIATION_RETAIN)
    }
}

struct AssociatedObject {
    static var key:UInt8 = 0
    static var footerBottomKey:UInt8 = 0
}

public extension UIScrollView{
    
    func configRefreshHeader(with refrehser:UIView & RefreshableHeader = DefaultRefreshHeader.header(),
                                    container object: AnyObject,
                                    action:@escaping ()->()){
        let oldContain = self.viewWithTag(PullToRefreshKitConst.headerTag)
        oldContain?.removeFromSuperview()
        let containFrame = CGRect(x: 0, y: -self.frame.height, width: self.frame.width, height: self.frame.height)
        let containComponent = RefreshHeaderContainer(frame: containFrame)
        if let endDuration = refrehser.durationOfHideAnimation?(){
            containComponent.durationOfEndRefreshing = endDuration
        }
        containComponent.tag = PullToRefreshKitConst.headerTag
        containComponent.refreshAction = action
        self.addSubview(containComponent)
        containComponent.delegate = refrehser
        refrehser.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        let refreshHeight = refrehser.heightForHeader()
        let bounds = CGRect(x: 0,y: containFrame.height - refreshHeight,width: self.frame.width,height: refreshHeight)
        refrehser.frame = bounds
        containComponent.addSubview(refrehser)
        configAssociatedObject(object: object)
    }
    
    func switchRefreshHeader(to state:HeaderRefresherState){
        let header = self.viewWithTag(PullToRefreshKitConst.headerTag) as? RefreshHeaderContainer
        switch state {
        case .refreshing:
            header?.beginRefreshing()
        case .normal(let result, let delay):
            header?.endRefreshing(result,delay: delay)
        case .removed:
            header?.removeFromSuperview()
        }
    }
}

// MARK: - Footer API  -

public enum FooterRefresherState {
    case refreshing //刷新中
    case normal //正常状态，转换到这个状态会结束刷新
    case noMoreData //没有数据，转换到这个状态会结束刷新
    case removed //移除
}


public extension UIScrollView{
    
    /// Whether footer should stay at the bottom of tableView when cells count is small.
    var footerAlwaysAtBottom:Bool{
        get{
            let object = objc_getAssociatedObject(self, &AssociatedObject.footerBottomKey)
            guard let number = object as? NSNumber else {
                return false
            }
            return number.boolValue
        }set{
            let number = NSNumber(value: newValue)
            objc_setAssociatedObject(self, &AssociatedObject.footerBottomKey, number, .OBJC_ASSOCIATION_RETAIN)
            guard let footerContainer = self.viewWithTag(PullToRefreshKitConst.footerTag) as? RefreshFooterContainer else{
                return;
            }
            footerContainer.handleContentSizeChange(nil)
        }
    }
    func configRefreshFooter(with refrehser:UIView & RefreshableFooter = DefaultRefreshFooter.footer(),
                                    container object: AnyObject,
                                    action:@escaping ()->()){
        let oldContain = self.viewWithTag(PullToRefreshKitConst.footerTag)
        oldContain?.removeFromSuperview()
        let containComponent = RefreshFooterContainer(frame: CGRect(x: 0, y: 0, width: self.frame.size.width, height: refrehser.heightForFooter()))
        containComponent.tag = PullToRefreshKitConst.footerTag
        containComponent.refreshAction = action
        self.insertSubview(containComponent, at: 0)
        containComponent.delegate = refrehser
        refrehser.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        refrehser.frame = containComponent.bounds
        containComponent.addSubview(refrehser)
        configAssociatedObject(object: object)
    }
    
    func switchRefreshFooter(to state:FooterRefresherState){
        let footer = self.viewWithTag(PullToRefreshKitConst.footerTag) as? RefreshFooterContainer
        switch state {
        case .refreshing:
            footer?.beginRefreshing()
        case .normal:
            footer?.endRefreshing()
            footer?.resetToDefault()
        case .noMoreData:
            footer?.endRefreshing()
            footer?.updateToNoMoreData()
        case .removed:
            footer?.removeFromSuperview()
        }
    }
}


// MARK: - Left & Right API  -

public enum SideRefreshDestination {
    case left,right
}

public extension UIScrollView{
    func configSideRefresh(with refrehser:UIView & RefreshableLeftRight,
                                  container object: AnyObject,
                                  at destination:SideRefreshDestination,
                                  action:@escaping ()->()){
        switch destination {
            case .left:
                let oldContain = self.viewWithTag(PullToRefreshKitConst.leftTag)
                oldContain?.removeFromSuperview()
                let frame = CGRect(x: -1.0 * refrehser.frame.size.width,
                                   y: 0.0,
                                   width: refrehser.widthForComponent(),
                                   height: self.frame.height)
                let containComponent = RefreshLeftContainer(frame: frame)
                containComponent.tag = PullToRefreshKitConst.leftTag
                containComponent.refreshAction = action
                self.insertSubview(containComponent, at: 0)
                containComponent.delegate = refrehser
                refrehser.autoresizingMask = [.flexibleWidth,.flexibleHeight]
                refrehser.frame = containComponent.bounds
                containComponent.addSubview(refrehser)
            case .right:
                let oldContain = self.viewWithTag(PullToRefreshKitConst.rightTag)
                oldContain?.removeFromSuperview()
                let frame = CGRect(x: 0 ,
                                   y: 0 ,
                                   width: refrehser.frame.size.width ,
                                   height: self.frame.height)
                let containComponent = RefreshRightContainer(frame: frame)
                containComponent.tag = PullToRefreshKitConst.rightTag
                containComponent.refreshAction = action
                self.insertSubview(containComponent, at: 0)
                
                containComponent.delegate = refrehser
                refrehser.autoresizingMask = [.flexibleWidth,.flexibleHeight]
                refrehser.frame = containComponent.bounds
                containComponent.addSubview(refrehser)
        }
        configAssociatedObject(object: object)
    }
    
    func removeSideRefresh(at destination:SideRefreshDestination){
        switch destination {
        case .left:
            let oldContain = self.viewWithTag(PullToRefreshKitConst.leftTag)
            oldContain?.removeFromSuperview()
        case .right:
            let oldContain = self.viewWithTag(PullToRefreshKitConst.rightTag)
            oldContain?.removeFromSuperview()
        }
    }
}
