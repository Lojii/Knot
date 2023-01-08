//
//  IDDialogUtil.swift
//  IDDialog
//
//  Created by darren on 2018/8/29.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit

public enum IDDialogUtilType {
    case normal  // 类似系统的弹框
    case image  // 带有图片的弹框
    case input // 可输入文字的弹框
    case custom // 自定义内容
}
public enum IDDialogUtilImageType {
    case success
    case fail
    case warning
}

class IDDialogUtil: Operation {
    
    lazy var coverView: UIView = {
        let cover = UIView.init(frame: CGRect.init(x: 0, y: 0, width: KScreenWidth, height: KScreenHeight))
        cover.alpha = 0.1
        cover.backgroundColor = UIColor.black
        return cover
    }()
    
    private var _executing = false
    override open var isExecuting: Bool {
        get {
            return self._executing
        }
        set {
            self.willChangeValue(forKey: "isExecuting")
            self._executing = newValue
            self.didChangeValue(forKey: "isExecuting")
        }
    }
    
    private var _finished = false
    override open var isFinished: Bool {
        get {
            return self._finished
        }
        set {
            self.willChangeValue(forKey: "isFinished")
            self._finished = newValue
            self.didChangeValue(forKey: "isFinished")
        }
    }
    
    var normalView: IDDialogNormalView? = IDDialogNormalView()   // 默认
    var imgView: IDDialogImageView? = IDDialogImageView()
    var inputView: IDDialogInputView? = IDDialogInputView()
    var customView: IDDialogCustomView? = IDDialogCustomView()

    var superComponent: UIView = (UIApplication.shared.keyWindow ?? UIView())
    var type = IDDialogUtilType.normal
    var imageType: IDDialogUtilImageType? = nil

    
    init(
        title: String? = nil,
        msg: String? = nil,
        leftActionTitle: String?,
        rightActionTitle: String?,
        leftHandler: (()->())? = nil,
        rightHandler:(()->())? = nil,
        countDownNumber: Int? = nil,
        success: IDDialogUtilImageType? = nil,
        type: IDDialogUtilType? = nil) {
        
        super.init()
        
        self.imageType = success
        self.type = type ?? IDDialogUtilType.normal
        
        if self.type == .normal {
            self.setupNormalView(title: title,msg: msg,leftActionTitle: leftActionTitle,rightActionTitle: rightActionTitle,leftHandler: leftHandler,rightHandler:rightHandler, countDownNumber: countDownNumber)
        }
        if self.type == .image {
            self.setupImageView(msg: msg,leftActionTitle: leftActionTitle,rightActionTitle: rightActionTitle,leftHandler: leftHandler,rightHandler:rightHandler)
        }

        self.commonUI()
    }
    /// 输入框类型
    init(
        msg: String? = nil,
        leftActionTitle: String?,
        rightActionTitle: String?,
        leftHandler: ((String)->())? = nil,
        rightHandler:((String)->())? = nil,
        type: IDDialogUtilType? = nil) {
        
        super.init()
        
        self.type = type ?? IDDialogUtilType.input

        self.setupInputView(msg: msg,leftActionTitle: leftActionTitle,rightActionTitle: rightActionTitle,leftHandler: leftHandler,rightHandler:rightHandler)
        
        self.commonUI()
    }
    
    /// 自定义类型
    init(
        msg: String? = nil,
        leftActionTitle: String?,
        rightActionTitle: String?,
        customView: UIView?,
        leftHandler: ((UIView?)->())? = nil,
        rightHandler:((UIView?)->())? = nil,
        type: IDDialogUtilType? = nil) {
        
        super.init()
        
        self.type = type ?? IDDialogUtilType.custom
        
        self.setupCustomView(msg: msg,leftActionTitle: leftActionTitle,rightActionTitle: rightActionTitle, customView: customView,leftHandler: leftHandler,rightHandler:rightHandler)
        
        self.commonUI()
    }
    
    func commonUI() {
        
        // 单利队列中每次都加入一个新建的Operation
        IDDialogManager.share.add(self)
        
        // 临时处理一下，如果没隔0.1秒就调用show,界面上会显示所有的dialog的叠加，dialog的阴影也会逐渐变黑，所以如果再很短的时间内，连续调用show，就只展示一个cover
        if IDDialogManager.share.queue.operationCount < 2 {
            self.superComponent.addSubview(self.coverView)
        }
        
        if self.coverView.superview != nil {
            self.coverView.translatesAutoresizingMaskIntoConstraints = false
            self.superComponent.addConstraints([
                NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.superComponent, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0),
                NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.superComponent, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0),
                NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.superComponent, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: 0),
                NSLayoutConstraint.init(item: self.coverView, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.superComponent, attribute: NSLayoutConstraint.Attribute.bottom, multiplier: 1, constant: 0),
                ])
        }
    }
    
    func setupNormalView(title: String? = nil,
                         msg: String? = nil,
                         leftActionTitle: String?,
                         rightActionTitle: String?,
                         leftHandler: (()->())? = nil,
                         rightHandler:(()->())? = nil,
                         countDownNumber: Int? = nil) {
        self.normalView = IDDialogNormalView()
        self.normalView?.title = title
        self.normalView?.msg = msg
        self.normalView?.leftActionTitle = leftActionTitle
        self.normalView?.rightActionTitle = rightActionTitle
        self.normalView?.countDownNumber = countDownNumber ?? 0
        self.normalView?.leftHandler = {() in
            self.dismiss()
            if leftHandler != nil {
                leftHandler!()
            }
        }
        self.normalView?.rightHandler = {() in
            self.dismiss()
            if rightHandler != nil {
                rightHandler!()
            }
        }
    }
    
    func setupImageView(msg: String? = nil,
                        leftActionTitle: String?,
                        rightActionTitle: String?,
                        leftHandler: (()->())? = nil,
                        rightHandler:(()->())? = nil) {
        self.imgView = IDDialogImageView()
        self.imgView?.msg = msg
        self.imgView?.leftActionTitle = leftActionTitle
        self.imgView?.rightActionTitle = rightActionTitle
        self.imgView?.leftHandler = {() in
            self.dismiss()
            if leftHandler != nil {
                leftHandler!()
            }
        }
        self.imgView?.rightHandler = {() in
            self.dismiss()
            if rightHandler != nil {
                rightHandler!()
            }
        }
    }
    func setupInputView(msg: String? = nil,
                        leftActionTitle: String?,
                        rightActionTitle: String?,
                        leftHandler: ((String)->())? = nil,
                        rightHandler:((String)->())? = nil) {
        self.inputView = IDDialogInputView()
        self.inputView?.msg = msg
        self.inputView?.leftActionTitle = leftActionTitle
        self.inputView?.rightActionTitle = rightActionTitle
        self.inputView?.leftHandler = {(text) in
            self.dismiss()
            if leftHandler != nil {
                leftHandler!(text)
            }
        }
        self.inputView?.rightHandler = {(text) in
            self.dismiss()
            if rightHandler != nil {
                rightHandler!(text)
            }
        }
    }
    
    func setupCustomView(msg: String? = nil,
                         leftActionTitle: String?,
                         rightActionTitle: String?,
                         customView: UIView?,
                         leftHandler: ((UIView?)->())? = nil,
                         rightHandler:((UIView?)->())? = nil) {
        self.customView = IDDialogCustomView()
        self.customView?.msg = msg
        self.customView?.customView = customView
        self.customView?.leftActionTitle = leftActionTitle
        self.customView?.rightActionTitle = rightActionTitle
        self.customView?.leftHandler = {(view) in
            self.dismiss()
            if leftHandler != nil {
                leftHandler!(view)
            }
        }
        self.customView?.rightHandler = {(view) in
            self.dismiss()
            if rightHandler != nil {
                rightHandler!(view)
            }
        }
    }

    open override func cancel() {
        super.cancel()
        self.dismiss()
    }
    override func start() {
        let isRunnable = !self.isFinished && !self.isCancelled && !self.isExecuting
        guard isRunnable else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
            return
        }
        main()
    }
    override func main() {
        self.isExecuting = true
        
        DispatchQueue.main.async {
            
            if self.type == .normal {
                self.showNormalView()
            }
            if self.type == .image {
                self.showImageView()
            }
            if self.type == .input {
                self.showInputView()
            }
            if self.type == .custom {
                self.showCustomView()
            }
        }
    }
    
    func showNormalView() {
        self.superComponent.addSubview(self.normalView ?? IDDialogNormalView())
        self.normalView?.msgLabel.textAlignment = IDDialogManager.share.textAlignment
        self.normalView?.setNeedsLayout()
        
        if IDDialogManager.share.supportAnimate {
            self.normalView?.layer.add(IDDialogManager.share.animate, forKey: nil)
        }
    }
    func showImageView() {
        self.superComponent.addSubview(self.imgView ?? IDDialogImageView())
        self.imgView?.msgLabel.textAlignment = IDDialogManager.share.textAlignment
        
        if self.imageType == .success {
            self.imgView?.iconView.image = IDDialogManager.share.successImage
        } else if self.imageType == .fail {
            self.imgView?.iconView.image = IDDialogManager.share.failImage
        } else if self.imageType == .warning {
            self.imgView?.iconView.image = IDDialogManager.share.warnImage
        } else {
            self.imgView?.iconView.image = nil
        }
        self.normalView?.setNeedsLayout()

        if IDDialogManager.share.supportAnimate {
            self.imgView?.layer.add(IDDialogManager.share.animate, forKey: nil)
        }
    }
    func showInputView() {
        self.superComponent.addSubview(self.inputView ?? IDDialogInputView())
        self.inputView?.msgLabel.textAlignment = IDDialogManager.share.textAlignment
        self.inputView?.setNeedsLayout()
        
        if IDDialogManager.share.supportAnimate {
            self.inputView?.layer.add(IDDialogManager.share.animate, forKey: nil)
        }
    }
    func showCustomView() {
        self.superComponent.addSubview(self.customView ?? IDDialogCustomView())
        self.customView?.msgLabel.textAlignment = IDDialogManager.share.textAlignment
        self.customView?.setNeedsLayout()
        
        if IDDialogManager.share.supportAnimate {
            self.customView?.layer.add(IDDialogManager.share.animate, forKey: nil)
        }
    }
}

extension IDDialogUtil {
    
    func dismiss() {
        
        UIView.animate(withDuration: 0.1, animations: {
            self.normalView?.alpha = 0.1
            self.imgView?.alpha = 0.1
            self.inputView?.alpha = 0.1
            self.customView?.alpha = 0.1
        }) { (finsh) in
            self.coverView.removeFromSuperview()
            self.normalView?.removeFromSuperview()
            self.imgView?.removeFromSuperview()
            self.inputView?.removeFromSuperview()
            self.customView?.removeFromSuperview()
            self.normalView = nil
            self.imgView = nil
            self.inputView = nil
            self.customView = nil

            self.finish()
        }
    }
    
    func finish() {
        self.isExecuting = false
        self.isFinished = true
        
        if IDDialogManager.share.supportQuene == false {
            IDDialogManager.share.cancelAll()
        }
    }
}
