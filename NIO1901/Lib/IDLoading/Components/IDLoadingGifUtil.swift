//
//  IDLoadingUtil.swift
//  IDLoading
//
//  Created by darren on 2018/11/22.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit

class IDLoadingGifUtil: NSObject {
    lazy var gifView: GifView = {
        let img = GifView()
        return img
    }()
    lazy var coverView: UIView = {
        let cover = UIView()
        cover.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        cover.backgroundColor = UIColor.black
        cover.alpha = 0.1
        return cover
    }()
    // gifName:gif图
    // type: 可以与用户交互，不可以与用户交互，默认不可以与用户交互
    init(gifName: String? = nil,type: IDLoadingUtilLoadingType? = nil, onView: UIView? = nil) {
        super.init()
        
        // 添加控件
        let superView = onView ?? UIApplication.shared.keyWindow
        let loadingType = type ?? .wait
        if loadingType == .wait {
            superView?.addSubview(self.coverView)
        }
        superView?.addSubview(self.gifView)
        
        // 更新尺寸
        self.updateGifViewFrame(superView: superView ?? UIView())
        
        if gifName == nil {
            self.gifView.showGIFImageWithLocalName(completionClosure: {
            })
        } else {
            let url = Bundle.main.url(forResource: gifName, withExtension: "gif")
            if url != nil {
                self.gifView.showGIFImageWithLocalName(gifUrl: url!, completionClosure: {
                    // 做动画执行后的操作
                })
            } else {
                print("未找到图片")
            }
        }
    }
    
    func updateGifViewFrame(superView: UIView) {
        
        if self.coverView.superview != nil {
            self.coverView.translatesAutoresizingMaskIntoConstraints = false
            superView.addConstraints([
                NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0),
                NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: 0),
                NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0),
                NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.bottom, multiplier: 1, constant: 0)
                ])
        }
        
        self.gifView.translatesAutoresizingMaskIntoConstraints = false
        self.gifView.addConstraint(NSLayoutConstraint.init(item: self.gifView, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 40))
        self.gifView.addConstraint(NSLayoutConstraint.init(item: self.gifView, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 40))
        superView.addConstraints([
            NSLayoutConstraint.init(item: self.gifView, attribute: NSLayoutConstraint.Attribute.centerX, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.centerX, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.gifView, attribute: NSLayoutConstraint.Attribute.centerY, relatedBy: NSLayoutConstraint.Relation.equal, toItem: superView, attribute: NSLayoutConstraint.Attribute.centerY, multiplier: 1, constant: 0),
            ])
    }
    
    func dismiss() {
        self.gifView.removeFromSuperview()
        self.coverView.removeFromSuperview()
    }
}
