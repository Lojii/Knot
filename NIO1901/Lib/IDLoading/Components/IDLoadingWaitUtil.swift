//
//  IDLoadingWaitUtil.swift
//  IDLoading
//
//  Created by darren on 2018/11/23.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit
class IDLoadingWaitUtil: NSObject {
    lazy var bottomView: UIView = {
        let bottom = UIView()
        bottom.frame = CGRect.zero
        bottom.backgroundColor = RGBAColor(0, 0, 0, 0.8)
        bottom.layer.cornerRadius = 4
        bottom.layer.masksToBounds = true
        return bottom
    }()
    lazy var progressView: IDRefreshLoadingView = {
        let progress = IDRefreshLoadingView.init(frame: CGRect.zero)
        progress.clouse = { [weak self] in
            self?.dismiss()
        }
        return progress
    }()
    lazy var coverView: UIView = {
        let cover = UIView()
        cover.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        cover.backgroundColor = UIColor.black
        cover.alpha = 0.1
        return cover
    }()
    // 展示阻止用户交互的控件
    init(onView: UIView? = nil) {
        super.init()
        
        // 添加控件
        let superView = onView ?? UIApplication.shared.keyWindow
        superView?.addSubview(self.coverView)
        superView?.addSubview(self.bottomView)
        self.bottomView.addSubview(self.progressView)
        
        // 更新尺寸
        self.updateFrame(superView: superView ?? UIView())
        
        // 动画显示
        self.progressView.start()
    }
    
    func updateFrame(superView: UIView) {
        self.bottomView.translatesAutoresizingMaskIntoConstraints = false
        self.progressView.translatesAutoresizingMaskIntoConstraints = false
        self.coverView.translatesAutoresizingMaskIntoConstraints = false
        
        superView.addConstraints([
            NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.bottom, multiplier: 1, constant: 0)
            ])
        
        self.bottomView.addConstraint(NSLayoutConstraint.init(item: self.bottomView, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 90))
        self.bottomView.addConstraint(NSLayoutConstraint.init(item: self.bottomView, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 90))
        superView.addConstraints([
            NSLayoutConstraint.init(item: self.bottomView, attribute: NSLayoutConstraint.Attribute.centerX, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.centerX, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.bottomView, attribute: NSLayoutConstraint.Attribute.centerY, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.centerY, multiplier: 1, constant: 0),
            ])
        
        self.progressView.addConstraint(NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 36))
        self.progressView.addConstraint(NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 36))
        bottomView.addConstraints([
            NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.centerY, relatedBy: NSLayoutConstraint.Relation.equal, toItem: bottomView, attribute: NSLayoutConstraint.Attribute.centerY, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.centerX, relatedBy: NSLayoutConstraint.Relation.equal, toItem: bottomView, attribute: NSLayoutConstraint.Attribute.centerX, multiplier: 1, constant: 0)
            ])
    }
    
    func dismiss() {
        UIView.animate(withDuration: 0.2, animations: {
            self.bottomView.alpha = 0
        }) { (finsh) in
            self.progressView.removeFromSuperview()
            self.coverView.removeFromSuperview()
            self.bottomView.removeFromSuperview()
            self.progressView.end()
        }
    }
}
