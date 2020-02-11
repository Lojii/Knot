//
//  ZKProgressHUD.swift
//  ZKProgressHUD
//
//  Created by 王文壮 on 2017/3/10.
//  Copyright © 2017年 WangWenzhuang. All rights reserved.
//

import UIKit

public typealias ZKCompletion = (() -> Void)

// MARK: - ZKProgressHUD
public class ZKProgressHUD: UIView {
    /// 全局中间变量
    fileprivate var hudType: HUDType!
    fileprivate var status: String?
    fileprivate var image: UIImage?
    fileprivate var gifUrl: URL?
    fileprivate var gifSize: CGFloat?
    fileprivate var progress: CGFloat?
    fileprivate var isShow: Bool = false
    fileprivate var statusFont: UIFont?
    fileprivate var maskStyle: MaskStyle?
    fileprivate var completion: ZKCompletion?
    
    fileprivate lazy var infoImage: UIImage? = Config.bundleImage(.info)?.withRenderingMode(.alwaysTemplate)
    fileprivate lazy var successImage: UIImage? = Config.bundleImage(.success)?.withRenderingMode(.alwaysTemplate)
    fileprivate lazy var errorImage: UIImage? = Config.bundleImage(.error)?.withRenderingMode(.alwaysTemplate)
    
    /// UI
    fileprivate lazy var screenView: UIView = {
        $0.mask?.alpha = 0.3
        $0.alpha = 0.3
        $0.backgroundColor = Config.maskBackgroundColor
        return $0
        
    }(UIView())
    
    fileprivate lazy var contentView: UIView = {
        $0.layer.masksToBounds = true
        $0.layer.cornerRadius = Config.cornerRadius
        if Config.effectStyle == .none {
            $0.backgroundColor = Config.backgroundColor
        } else {
            $0.backgroundColor = .clear
        }
        $0.alpha = 0
        return $0
    }(UIView())
    
    
    fileprivate var blurEffectStyle: UIBlurEffect.Style {
        get {
            switch Config.effectStyle {
            case .extraLight:
                return .extraLight
            case .light:
                return .light
            default:
                return .dark
            }
        }
    }
    
    fileprivate lazy var contentBlurView: UIVisualEffectView = {
        $0.alpha = Config.effectAlpha
        return $0
    }(UIVisualEffectView(effect: UIBlurEffect(style: self.blurEffectStyle)))
    
    /// gif(ZKProgressHUDType)
    fileprivate lazy var gifView: ZKGifView = ZKGifView()
    
    /// image(ZKProgressHUDType)
    fileprivate lazy var imageView: UIImageView = {
        $0.contentMode = .scaleToFill
        $0.tintColor = Config.foregroundColor
        return $0
    }(UIImageView())
    
    /// progress(ZKProgressHUDType)
    fileprivate lazy var progressView: ZKProgressView = {
        $0.progressColor = Config.foregroundColor
        $0.backgroundColor = .clear
        return $0
    }(ZKProgressView(frame: CGRect(x: 0, y: 0, width: 85, height: 85)))
    
    /// activityIndicator(ZKProgressHUDType)
    fileprivate var activityIndicatorView: UIView {
        return Config.animationStyle == AnimationStyle.circle ? self.circleHUDView : self.systemHUDView
    }
    
    fileprivate lazy var systemHUDView: UIActivityIndicatorView = {
        $0.style = .whiteLarge
        $0.color = Config.foregroundColor
        $0.sizeToFit()
        $0.startAnimating()
        return $0
    }(UIActivityIndicatorView())
    
    fileprivate lazy var circleHUDView: UIView = { view in
        view.frame = CGRect(
            x: 0,
            y: 0,
            width: 65,
            height: 65
        )
        let lineWidth: CGFloat = 3
        let lineMargin: CGFloat = lineWidth / 2
        let arcCenter = CGPoint(x: view.width / 2 - lineMargin, y: view.height / 2 - lineMargin)
        let smoothedPath = UIBezierPath(
            arcCenter: arcCenter,
            radius: view.width / 2 - lineWidth,
            startAngle: 0,
            endAngle: CGFloat(Double.pi * 2),
            clockwise: true
        )
        
        let layer: CAShapeLayer = {
            $0.contentsScale = UIScreen.main.scale
            $0.frame = CGRect(x: lineMargin, y: lineMargin, width: arcCenter.x * 2, height: arcCenter.y * 2)
            $0.fillColor = UIColor.clear.cgColor
            $0.strokeColor = Config.foregroundColor.cgColor
            $0.lineWidth = 3
            $0.lineCap = CAShapeLayerLineCap.round
            $0.lineJoin = CAShapeLayerLineJoin.bevel
            $0.path = smoothedPath.cgPath
            $0.mask = CALayer()
            $0.mask?.contents = Config.bundleImage(.mask)?.cgImage
            $0.mask?.frame = $0.bounds
            return $0
        }(CAShapeLayer())
        
        let animation: CABasicAnimation = {
            $0.fromValue = 0
            $0.toValue = (Double.pi * 2)
            $0.duration = 1
            $0.isRemovedOnCompletion = false
            $0.repeatCount = Float(Int.max)
            $0.autoreverses = false
            return $0
        }(CABasicAnimation(keyPath: "transform.rotation"))
        
        layer.add(animation, forKey: "rotate")
        
        view.layer.addSublayer(layer)
        return view
    }(UIView())
    
    fileprivate lazy var statusLabel: UILabel = {
        $0.textAlignment = .center
        $0.numberOfLines = 0
        $0.textColor = Config.foregroundColor
        return $0
    }(UILabel())
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ZKProgressHUD.observerDismiss),
            name: Config.ZKNSNotificationDismiss,
            object: nil
        )
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: Config.ZKNSNotificationDismiss, object: nil)
    }
}

// MARK: - 实例计算属性
extension ZKProgressHUD {
    fileprivate var screenWidht: CGFloat {
        return UIScreen.main.bounds.size.width
    }
    
    fileprivate var screenHeight: CGFloat {
        return UIScreen.main.bounds.size.height
    }
    
    fileprivate var maxContentViewWidth: CGFloat {
        return self.screenWidht - Config.margin * 2
    }
    
    fileprivate var maxContentViewChildWidth: CGFloat {
        return self.screenWidht - Config.margin * 4
    }
}

extension ZKProgressHUD {
    /// 显示
    fileprivate func show(hudType: HUDType,
                          status: String? = nil,
                          image: UIImage? = nil,
                          isAutoDismiss: Bool? = nil,
                          maskStyle: MaskStyle? = nil,
                          imageType: ImageType? = nil,
                          gifUrl: URL? = nil,
                          gifSize: CGFloat? = nil,
                          progress: CGFloat? = nil,
                          completion: ZKCompletion? = nil,
                          onlyOnceFont: UIFont? = nil,
                          autoDismissDelay: Double? = nil) {
        DispatchQueue.main.async {
            self.hudType = hudType
            self.status = status == "" ? nil : status
            self.image = image
            self.gifUrl = gifUrl
            self.gifSize = gifSize
            self.progress = progress ?? 0
            self.statusFont = onlyOnceFont
            self.maskStyle = maskStyle
            self.completion = completion
            if let imgType = imageType {
                switch imgType {
                case .info:
                    self.image = self.infoImage
                case .error:
                    self.image = self.errorImage
                case .success:
                    self.image = self.successImage
                default: break
                }
            }
            if self.hudType == .progress {
                if let progressValue = self.progress {
                    self.progressView.progress = Double(progressValue)
                }
                if self.restorationIdentifier != Config.restorationIdentifier {
                    self.updateView()
                }
            } else {
                self.updateView()
            }
            
            self.updateFrame()
            if !self.isShow {
                self.animationShow(contentFrame: self.contentView.frame)
            }
            if let autoDismiss = isAutoDismiss {
                if autoDismiss {
                    self.autoDismiss(delay: autoDismissDelay ?? Config.autoDismissDelay)
                }
            }
        }
    }
    /// 更新视图
    fileprivate func updateView() {
        self.restorationIdentifier = Config.restorationIdentifier
        UIWindow.frontWindow?.addSubview(self)
        if (self.maskStyle ?? Config.maskStyle) == .visible {
            self.addSubview(self.screenView)
        }
        self.addSubview(self.contentView)
        if Config.effectStyle != .none {
            self.contentView.addSubview(self.contentBlurView)
        }
        self.contentView.addSubview(self.statusLabel)
        switch self.hudType! {
        case .gif:
            if let url = self.gifUrl {
                self.gifView.frame.size = CGSize(width: self.gifSize ?? 100, height: self.gifSize ?? 100)
                self.gifView.showGIFImage(gifUrl: url)
                self.contentView.addSubview(self.gifView)
            }
            break
        case .image:
            self.contentView.addSubview(self.imageView)
            break
        case .progress:
            self.contentView.addSubview(self.progressView)
            break
        case .activityIndicator:
            self.contentView.addSubview(self.activityIndicatorView)
        default: break
        }
    }
    public override func layoutSubviews() {
        updateFrame()
    }
    /// 更新视图大小坐标
    fileprivate func updateFrame() {
        screenView.frame.size = CGSize(width: self.screenWidht, height: self.screenHeight)
        if self.hudType! == .gif {
            if self.gifView.width > self.maxContentViewChildWidth {
                self.gifView.frame.size = CGSize(width: self.maxContentViewChildWidth, height: self.maxContentViewChildWidth)
            }
        }
        if self.hudType! == .image {
            self.imageView.image = self.image
            self.imageView.sizeToFit()
            // 如果图片尺寸超过限定最大尺寸，将图片尺寸修改为限定最大尺寸
            if self.imageView.width > self.maxContentViewChildWidth {
                self.imageView.frame.size = CGSize(width: self.maxContentViewChildWidth, height: self.maxContentViewChildWidth)
            }
        }
        
        if let text = self.status {
            self.statusLabel.isHidden = false
            self.statusLabel.text = text
            self.statusLabel.font = self.statusFont ?? Config.font
            self.statusLabel.frame.size = text.size(font: self.statusFont ?? Config.font, size: CGSize(width: self.maxContentViewChildWidth, height: 400))
        } else {
            self.statusLabel.frame.size = CGSize.zero
            self.statusLabel.isHidden = true
        }
        
        self.contentView.frame.size = {
            var width: CGFloat = 0
            switch self.hudType! {
            case .gif:
                width = (self.statusLabel.isHidden ? self.gifView.width : (self.gifView.width > self.statusLabel.width ? self.gifView.width : self.statusLabel.width)) + Config.margin * 2
            case .image:
                width = (self.statusLabel.isHidden ? self.imageView.width : (self.imageView.width > self.statusLabel.width ? self.imageView.width : self.statusLabel.width)) + Config.margin * 2
            case .message:
                width = self.statusLabel.width + Config.margin * 2
            case .progress:
                width = (self.statusLabel.isHidden ? self.progressView.width : (self.progressView.width > self.statusLabel.width ? self.progressView.width : self.statusLabel.width)) + Config.margin * 2
            case .activityIndicator:
                width = (self.statusLabel.isHidden ? self.activityIndicatorView.width : (self.activityIndicatorView.width > self.statusLabel.width ? self.activityIndicatorView.width : self.statusLabel.width)) + Config.margin * 2
            }
            
            var height: CGFloat = 0
            switch self.hudType! {
            case .gif:
                height = (self.statusLabel.isHidden ? self.gifView.height : (self.gifView.height + Config.margin + self.statusLabel.height)) + Config.margin * 2
            case .image:
                height = (self.statusLabel.isHidden ? self.imageView.height : (self.imageView.height + Config.margin + self.statusLabel.height)) + Config.margin * 2
            case .message:
                height = self.statusLabel.height + Config.margin * 2
            case .progress:
                height = (self.statusLabel.isHidden ? self.progressView.height : (self.progressView.height + Config.margin + self.statusLabel.height)) + Config.margin * 2
            case .activityIndicator:
                height = (self.statusLabel.isHidden ? self.activityIndicatorView.height : (self.activityIndicatorView.height + Config.margin + self.statusLabel.height)) + Config.margin * 2
            }
            
            return CGSize(width: width, height: height)
        }()
        
        self.contentBlurView.frame = CGRect(x: 0, y: 0, width: self.contentView.width, height: self.contentView.height)
        switch self.hudType! {
        case .gif:
            self.gifView.frame.origin = {
                let x = (self.contentView.width - self.gifView.width) / 2
                let y = Config.margin
                return CGPoint(x: x, y: y)
            }()
            self.statusLabel.frame.origin = {
                let x = (self.contentView.width - self.statusLabel.width) / 2
                let y = self.gifView.y + self.gifView.height + Config.margin
                return CGPoint(x: x, y: y)
            }()
        case .image:
            self.imageView.frame.origin = {
                let x = (self.contentView.width - self.imageView.width) / 2
                let y = Config.margin
                return CGPoint(x: x, y: y)
            }()
            self.statusLabel.frame.origin = {
                let x = (self.contentView.width - self.statusLabel.width) / 2
                let y = self.imageView.y + self.imageView.height + Config.margin
                return CGPoint(x: x, y: y)
            }()
        case .message:
            self.statusLabel.frame.origin = {
                let x = (self.contentView.width - self.statusLabel.width) / 2
                let y = Config.margin
                return CGPoint(x: x, y: y)
            }()
        case .progress:
            self.progressView.frame.origin = {
                let x = (self.contentView.width - self.progressView.width) / 2
                let y = Config.margin
                return CGPoint(x: x, y: y)
            }()
            self.statusLabel.frame.origin = {
                let x = (self.contentView.width - self.statusLabel.width) / 2
                let y = self.progressView.y + self.progressView.height + Config.margin
                return CGPoint(x: x, y: y)
            }()
        case .activityIndicator:
            self.activityIndicatorView.frame.origin = {
                let x = (self.contentView.width - self.activityIndicatorView.width) / 2
                let y = Config.margin
                return CGPoint(x: x, y: y)
            }()
            self.statusLabel.frame.origin = {
                let x = (self.contentView.width - self.statusLabel.width) / 2
                let y = self.activityIndicatorView.y + self.activityIndicatorView.height + Config.margin
                return CGPoint(x: x, y: y)
            }()
        }
        
        let x = (self.screenWidht - self.contentView.width) / 2
        let y = (self.screenHeight - self.contentView.height) / 2
        if (self.maskStyle ?? Config.maskStyle) == .hide {
            self.frame = CGRect(x: x, y: y, width: self.contentView.width, height: self.contentView.height)
            self.contentView.frame.origin = CGPoint(x: 0, y: 0)
        } else {
            self.frame = CGRect(x: 0, y: 0, width: self.screenWidht, height: self.screenHeight)
            self.contentView.frame.origin = CGPoint(x: x, y: y)
        }
    }
    /// 动画显示
    func animationShow(contentFrame: CGRect) {
        self.isShow = true
        switch Config.animationShowStyle {
        case .fade:
            self.contentView.alpha = 0
        case .zoom:
            self.contentView.alpha = 1
            self.contentView.frame = CGRect(
                x: self.screenWidht / 2,
                y: contentFrame.origin.y,
                width: 0,
                height: contentFrame.size.height
            )
        case .flyInto:
            self.contentView.alpha = 1
            self.contentView.frame = CGRect(
                x: contentFrame.origin.x,
                y: 0 - contentFrame.size.height,
                width: contentFrame.size.width,
                height: contentFrame.size.height
            )
            break
        }
        UIView.animate(withDuration: 0.3, animations: {
            switch Config.animationShowStyle {
            case .fade:
                self.contentView.alpha = 1
            case .zoom:
                self.contentView.frame = contentFrame
            case .flyInto:
                self.contentView.frame = contentFrame
                break
            }
        })
    }
    /// 动画移除
    func animationDsmiss() {
        UIView.animate(withDuration: 0.3, animations: {
            switch Config.animationShowStyle {
            case .fade:
                self.contentView.alpha = 0
            case .zoom:
                self.contentView.frame = CGRect(
                    x: self.screenWidht / 2,
                    y: self.contentView.y,
                    width: 0,
                    height: self.contentView.height
                )
            case .flyInto:
                self.contentView.frame = CGRect(
                    x: self.contentView.x,
                    y: 0 - self.contentView.height,
                    width: self.contentView.width,
                    height: self.contentView.height
                )
                break
            }
        }, completion: { (finished) in
            self.isShow = false
            self.removeFromSuperview()
            self.completion?()
        })
    }
    /// 通知移除
    @objc fileprivate func observerDismiss(notification: Notification) {
        if let userInfo = notification.userInfo {
            let delay = userInfo["delay"] as! Double
            self.autoDismiss(delay: delay)
        } else {
            self.isShow = false
            self.removeFromSuperview()
        }
    }
    /// 自动移除
    fileprivate func autoDismiss(delay: Double) {
        let a = Int(delay * 1000 * 1000)
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .microseconds(a), execute: {
            DispatchQueue.main.async {
                self.animationDsmiss()
            }
        })
    }
}

// MARK: - 类计算属性
extension ZKProgressHUD {
    static var shared: ZKProgressHUD {
        return ZKProgressHUD(frame: UIScreen.main.bounds)
    }
}

// MARK: - 类方法
extension ZKProgressHUD {
    /// 显示gif加载
    public static func showGif(
        gifUrl: URL?, gifSize: CGFloat?, status: String? = nil, maskStyle: ZKProgressHUDMaskStyle? = nil, onlyOnceFont: UIFont? = nil) {
        shared.show(hudType: .gif, status: status, maskStyle: maskStyle, gifUrl: gifUrl, gifSize: gifSize, onlyOnceFont: onlyOnceFont)
    }
    
    /// 显示图片
    public static func showImage(_ image: UIImage?, status: String? = nil, maskStyle: ZKProgressHUDMaskStyle? = nil, onlyOnceFont: UIFont? = nil, autoDismissDelay: Double? = nil, completion: ZKCompletion? = nil) {
        shared.show(hudType: .image, status: status, image: image, isAutoDismiss: true, maskStyle: maskStyle, completion: completion, onlyOnceFont: onlyOnceFont, autoDismissDelay: autoDismissDelay)
    }
    
    /// 显示消息
    public static func showMessage(_ message: String?, maskStyle: ZKProgressHUDMaskStyle? = nil, onlyOnceFont: UIFont? = nil, autoDismissDelay: Double? = nil, completion: ZKCompletion? = nil) {
        shared.show(hudType: .message, status: message, isAutoDismiss: true, maskStyle: maskStyle, completion: completion, onlyOnceFont: onlyOnceFont, autoDismissDelay: autoDismissDelay)
    }
    
    /// 显示进度
    public static func showProgress(_ progress: CGFloat?, status: String? = nil, maskStyle: ZKProgressHUDMaskStyle? = nil, onlyOnceFont: UIFont? = nil) {
        var isShowProgressView = false
        for subview in (UIWindow.frontWindow?.subviews)! {
            if subview.isKind(of: ZKProgressHUD.self) && subview.restorationIdentifier == Config.restorationIdentifier {
                let progressHUD = subview as! ZKProgressHUD
                if progressHUD.hudType == .progress {
                    progressHUD.show(hudType: .progress, status: status, maskStyle: maskStyle, progress: progress, onlyOnceFont: onlyOnceFont)
                    isShowProgressView = true
                } else {
                    progressHUD.removeFromSuperview()
                }
            }
        }
        if !isShowProgressView {
            shared.show(hudType: .progress, status: status, maskStyle: maskStyle, progress: progress, onlyOnceFont: onlyOnceFont)
        }
    }
    
    /// 显示加载
    public static func show(_ status: String? = nil, maskStyle: ZKProgressHUDMaskStyle? = nil, onlyOnceFont: UIFont? = nil) {
        shared.show(hudType: .activityIndicator, status: status, maskStyle: maskStyle, onlyOnceFont: onlyOnceFont)
    }
    
    /// 显示普通信息
    public static func showInfo(_ status: String? = nil, maskStyle: ZKProgressHUDMaskStyle? = nil, onlyOnceFont: UIFont? = nil, autoDismissDelay: Double? = nil, completion: ZKCompletion? = nil) {
        shared.show(hudType: .image, status: status, isAutoDismiss: true, maskStyle: maskStyle, imageType: .info, completion: completion, onlyOnceFont: onlyOnceFont, autoDismissDelay: autoDismissDelay)
    }
    
    /// 显示成功信息
    public static func showSuccess(_ status: String? = nil, maskStyle: ZKProgressHUDMaskStyle? = nil, onlyOnceFont: UIFont? = nil, autoDismissDelay: Double? = nil, completion: ZKCompletion? = nil) {
        shared.show(hudType: .image, status: status, isAutoDismiss: true, maskStyle: maskStyle, imageType: .success, completion: completion, onlyOnceFont: onlyOnceFont, autoDismissDelay: autoDismissDelay)
    }
    
    /// 显示失败信息
    public static func showError(_ status: String?, maskStyle: ZKProgressHUDMaskStyle? = nil, onlyOnceFont: UIFont? = nil, autoDismissDelay: Double? = nil, completion: ZKCompletion? = nil) {
        shared.show(hudType: .image, status: status, isAutoDismiss: true, maskStyle: maskStyle, imageType: .error, completion: completion, onlyOnceFont: onlyOnceFont, autoDismissDelay: autoDismissDelay)
    }
    
    @available(swift, deprecated: 3.0, message: "请使用 dismiss 方法")
    public static func hide(delay: Double? = nil) {
        ZKProgressHUD.dismiss(delay)
    }
    /// 移除
    public static func dismiss(_ delay: Double? = nil) {
        NotificationCenter.default.post(name: Config.ZKNSNotificationDismiss, object: nil, userInfo: ["delay" : delay ?? 0])
    }
    
    /// 设置遮罩样式，默认值：.visible
    public static func setMaskStyle (_ maskStyle: ZKProgressHUDMaskStyle) {
        Config.maskStyle = maskStyle
    }
    
    /// 设置动画显示/隐藏样式，默认值：.fade
    public static func setAnimationShowStyle (_ animationShowStyle: ZKProgressHUDAnimationShowStyle) {
        Config.animationShowStyle = animationShowStyle
    }
    
    /// 设置遮罩背景色，默认值：.black
    public static func setMaskBackgroundColor(_ color: UIColor) {
        Config.effectStyle = .none
        Config.maskBackgroundColor = color
    }
    
    /// 设置前景色，默认值：.white（前景色在设置 effectStyle 值时会自动适配，如果要使用自定义前景色，在调用 setEffectStyle 方法后调用 setForegroundColor 方法即可）
    public static func setForegroundColor(_ color: UIColor) {
        Config.foregroundColor = color
    }
    /// 设置 HUD 毛玻璃效果（与 backgroundColor 互斥，如果设置毛玻璃效果不是.none，则根据样式自动设置前景色），默认值：.dark
    public static func setEffectStyle(_ hudEffectStyle: ZKProgressHUDEffectStyle) {
        Config.effectStyle = hudEffectStyle
        if hudEffectStyle == .light || hudEffectStyle == .extraLight {
            Config.foregroundColor = .black
        } else if hudEffectStyle == .dark {
            Config.foregroundColor = .white
        }
    }
    /// 设置 HUD 毛玻璃透明度，默认值：1
    public static func setEffectAlpha(_ effectAlpha: CGFloat) {
        Config.effectAlpha = effectAlpha
    }
    /// 设置 HUD 背景色（与 effectStyle 互斥，如果设置背景色，effectStyle = .none），默认值：UIColor(red: 0 / 255.0, green: 0 / 255.0, blue: 0 / 255.0, alpha: 0.8)
    public static func setBackgroundColor(_ color: UIColor) {
        Config.backgroundColor = color
        Config.effectStyle = .none
    }
    
    /// 设置字体，默认值：UIFont.boldSystemFont(ofSize: 15)
    public static func setFont(_ font: UIFont) {
        Config.font = font
    }
    
    /// 设置圆角，默认值：6
    public static func setCornerRadius(_ cornerRadius: CGFloat) {
        Config.cornerRadius = cornerRadius
    }
    
    /// 设置加载动画样式动画样式，默认值：circle
    public static func setAnimationStyle(_ animationStyle: ZKProgressHUDAnimationStyle) {
        Config.animationStyle  = animationStyle
    }
    
    /// 设置自动隐藏延时秒数，默认值：2
    public static func setAutoDismissDelay(_ autoDismissDelay: Double) {
        Config.autoDismissDelay = autoDismissDelay
    }
}
