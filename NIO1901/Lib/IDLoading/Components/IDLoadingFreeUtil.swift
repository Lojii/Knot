//
//  IDLoadingFreeUtil.swift
//  IDLoading
//
//  Created by darren on 2018/11/23.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit
class IDLoadingFreeUtil: NSObject {
    lazy var bottomView: UIView = {
        let bottom = UIView()
        bottom.frame = CGRect.zero
        return bottom
    }()
    lazy var progressView: IDRefreshLoadingView = {
        let progress = IDRefreshLoadingView.init(frame: CGRect.zero)
        progress.clouse = { [weak self] in
            self?.dismiss()
        }
        return progress
    }()
    lazy var titleLabel: UILabel = {
        let title = UILabel.init(frame: CGRect.zero)
        title.font = UIFont.systemFont(ofSize: 14)
        title.textColor = RGBAColor(96, 102, 111, 1)
        title.text = "加载中..."
        title.textAlignment = .center
        return title
    }()
    // 展示不带遮罩层
    init(onView: UIView? = nil) {
        super.init()
        
        // 添加控件
        let superView = onView ?? UIApplication.shared.keyWindow
        superView?.addSubview(self.bottomView)
        self.bottomView.addSubview(self.progressView)
        self.bottomView.addSubview(self.titleLabel)
        
        // 更新尺寸
        self.updateFrame(superView: superView ?? UIView())
        
        self.progressView.start()
    }
    
    func updateFrame(superView: UIView) {
        
        self.bottomView.translatesAutoresizingMaskIntoConstraints = false
        self.progressView.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false

        self.bottomView.addConstraint(NSLayoutConstraint.init(item: self.bottomView, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 90))
        self.bottomView.addConstraint(NSLayoutConstraint.init(item: self.bottomView, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 90))
        superView.addConstraints([
            NSLayoutConstraint.init(item: self.bottomView, attribute: NSLayoutConstraint.Attribute.centerX, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.centerX, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.bottomView, attribute: NSLayoutConstraint.Attribute.centerY, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.centerY, multiplier: 1, constant: 0),
            ])
        
        self.progressView.addConstraint(NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 36))
        self.progressView.addConstraint(NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 36))
        bottomView.addConstraints([
            NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: bottomView, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.centerX, relatedBy: NSLayoutConstraint.Relation.equal, toItem: bottomView, attribute: NSLayoutConstraint.Attribute.centerX, multiplier: 1, constant: 0)
            ])
        
        self.titleLabel.addConstraint(NSLayoutConstraint.init(item: self.titleLabel, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 25))
        bottomView.addConstraints([
            NSLayoutConstraint.init(item: self.titleLabel, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: bottomView, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.titleLabel, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: bottomView, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: 42),
            NSLayoutConstraint.init(item: self.titleLabel, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: bottomView, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0)
            ])
    }
    
    func dismiss() {
        UIView.animate(withDuration: 0.2, animations: {
            self.bottomView.alpha = 0
        }) { (finsh) in
            self.progressView.removeFromSuperview()
            self.titleLabel.removeFromSuperview()
            self.bottomView.removeFromSuperview()
            self.progressView.end()
        }
    }
}
