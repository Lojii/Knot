//
//  IDLoadingNavUtil.swift
//  IDLoading
//
//  Created by darren on 2018/11/23.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit
class IDLoadingNavUtil: NSObject {
    
    var superView: UIView = UIView()
    var timer: DispatchSourceTimer?

    lazy var progressView: NavProgressView = {
        let progress = NavProgressView.init(frame: CGRect.init(x: 0, y: self.superView.frame.height-2, width: self.superView.frame.width, height: 2))
        return progress
    }()
    // 导航栏进度条
    init(onView: UIView, colors: [CGColor]? = nil) {
        super.init()
        
        self.superView = onView
        
        onView.addSubview(self.progressView)
        if colors != nil {
            self.progressView.colors = colors!
        }
        // 尺寸
        self.updateFrame(superView: onView)
        
        // 开启定时器，加载进度
        self.setupTimer()
    }
    
    func setupTimer() {
        self.timer = DispatchSource.makeTimerSource(queue: .main)
        self.timer?.schedule(deadline: .now(), repeating: 0.1)
        self.timer?.setEventHandler(handler: {() -> Void in
            if self.progressView.progress < 0.8 {
                self.progressView.progress = self.progressView.progress + 0.1
            }
            if (self.progressView.progress >= 0.8) {
                self.progressView.progress = self.progressView.progress + 0.001
            }
            
            if (self.progressView.progress >= 0.9) {
                self.progressView.progress = 0.9
            }
        })
        self.timer?.resume()
    }
    
    func updateFrame(superView: UIView) {
        self.progressView.translatesAutoresizingMaskIntoConstraints = false

        self.progressView.addConstraint(NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 2))

        superView.addConstraints([
            NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.progressView, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.bottom, multiplier: 1, constant: -2)
            ])
    }
    
    func dismiss() {
        self.timer?.cancel()
        self.timer = nil
        self.progressView.progress = 1

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) {
            self.progressView.removeFromSuperview()
        }
    }
}
