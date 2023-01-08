//
//  PullToRefreshHeader.swift
//  PullToRefreshKit
//
//  Created by huangwenchen on 16/7/11.
//  I refer a lot logic for MJRefresh https://github.com/CoderMJLee/MJRefresh ,thanks to this lib and all contributors.
//  Copyright © 2016年 Leo. All rights reserved.
//

import Foundation
import UIKit

@objc public protocol RefreshableHeader: class{
    /**
     视图的高度
     */
    func heightForHeader()->CGFloat
    
    /**
     进入刷新状态的回调，在这里将视图调整为刷新中
     */
    func didBeginRefreshingState()
    
    /**
     刷新结束，将要进行隐藏的动画，一般在这里告诉用户刷新的结果
     - parameter result: 刷新结果
     */
    func didBeginHideAnimation(_ result:RefreshResult)
    /**
     刷新结束，隐藏的动画结束，一般在这里把视图隐藏，各个参数恢复到最初状态
     
     - parameter result: 刷新结果
     */
    func didCompleteHideAnimation(_ result:RefreshResult)
    
    /**
     状态改变
     
     - parameter newState: 新的状态
     - parameter oldState: 老得状态
     */
    @objc optional func stateDidChanged(_ oldState:RefreshHeaderState, newState:RefreshHeaderState)
    
    /**
     触发刷新的时候，距离顶部的高度，可选，如果没有实现，则默认触发刷新的距离就是 heightForHeader
     */
    @objc optional func heightForFireRefreshing()->CGFloat
    
    /**
     在刷新状态的时候，距离顶部的高度，默认是heightForHeader
     */
    @objc optional func heightForRefreshingState()->CGFloat
    /**
     不在刷新状态的时候，百分比回调，在这里你根据百分比来动态的调整你的刷新视图
     - parameter percent: 拖拽的百分比，比如一共距离是100，那么拖拽10的时候，percent就是0.1
     */
    @objc optional func percentUpdateDuringScrolling(_ percent:CGFloat)

    /**
     刷新结束，隐藏header的时间间隔，默认0.4s
     
     */
    @objc optional func durationOfHideAnimation()->Double
}

public enum RefreshKitHeaderText{
    case pullToRefresh
    case releaseToRefresh
    case refreshSuccess
    case refreshFailure
    case refreshing
}
/**
 Header所处的状态
 
 - Idle:        最初
 - Pulling:     下拉
 - Refreshing:  正在刷新中
 - WillRefresh: 将要刷新
 */
@objc public enum RefreshHeaderState:Int{
    case idle = 0
    case pulling = 1
    case refreshing = 2
    case willRefresh = 3
}

open class DefaultRefreshHeader: UIView, RefreshableHeader {
    
    open class func header()->DefaultRefreshHeader{
        return DefaultRefreshHeader();
    }
    
    open var imageRenderingWithTintColor = false{
        didSet{
            if imageRenderingWithTintColor{
                imageView.image = imageView.image?.withRenderingMode(.alwaysTemplate)
            }
        }
    }
    
    #if swift(>=4.2)
    public let spinner:UIActivityIndicatorView = UIActivityIndicatorView(style: .gray)
    #else
    public let spinner:UIActivityIndicatorView = UIActivityIndicatorView(activityIndicatorStyle: .gray)
    #endif
    public let textLabel:UILabel = UILabel(frame: CGRect(x: 0,y: 0,width: 140,height: 40))
    public let imageView:UIImageView = UIImageView(frame: CGRect.zero)
    open var durationWhenHide = 0.5
    fileprivate var textDic = [RefreshKitHeaderText:String]()
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(spinner)
        addSubview(textLabel)
        addSubview(imageView);
        let image = UIImage(named: "arrow_down", in: Bundle(for: DefaultRefreshHeader.self), compatibleWith: nil)
        imageView.image = image
        imageView.sizeToFit()
        textLabel.font = UIFont.systemFont(ofSize: 14)
        textLabel.textAlignment = .center
        self.isHidden = true
        //Default text
        textDic[.pullToRefresh] = PullToRefreshKitHeaderString.pullDownToRefresh
        textDic[.releaseToRefresh] = PullToRefreshKitHeaderString.releaseToRefresh
        textDic[.refreshSuccess] = PullToRefreshKitHeaderString.refreshSuccess
        textDic[.refreshFailure] = PullToRefreshKitHeaderString.refreshFailure
        textDic[.refreshing] = PullToRefreshKitHeaderString.refreshing
        textLabel.text = textDic[.pullToRefresh]
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        imageView.center = CGPoint(x: frame.width/2 - 70 - 20, y: frame.size.height/2)
        spinner.center = imageView.center
        textLabel.center = CGPoint(x: frame.size.width/2, y: frame.size.height/2);
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open func setText(_ text:String,mode:RefreshKitHeaderText){
        textDic[mode] = text
    }
    
    // MARK: - Refreshable  -
    public func heightForHeader() -> CGFloat {
        return PullToRefreshKitConst.defaultHeaderHeight
    }
    
    public func percentUpdateDuringScrolling(_ percent: CGFloat) {
        self.isHidden = false
    }
    
    public func stateDidChanged(_ oldState: RefreshHeaderState, newState: RefreshHeaderState) {
        if oldState == RefreshHeaderState.idle && newState == RefreshHeaderState.pulling{
            textLabel.text = textDic[.releaseToRefresh]
            guard self.imageView.transform == CGAffineTransform.identity else{
                return
            }
            UIView.animate(withDuration: 0.4, animations: {
                self.imageView.transform = CGAffineTransform(rotationAngle: -CGFloat.pi+0.000001)
            })
        }
        if oldState == RefreshHeaderState.pulling && newState == RefreshHeaderState.idle {
            textLabel.text = textDic[.pullToRefresh]
            guard self.imageView.transform == CGAffineTransform(rotationAngle: -CGFloat.pi+0.000001)  else{
                return
            }
            UIView.animate(withDuration: 0.4, animations: {
                self.imageView.transform = CGAffineTransform.identity
            })
        }
    }
    
    open func durationOfHideAnimation() -> Double {
        return durationWhenHide
    }
    
    open func didBeginHideAnimation(_ result:RefreshResult) {
        spinner.stopAnimating()
        imageView.transform = CGAffineTransform.identity
        imageView.isHidden = false
        switch result {
        case .success:
            textLabel.text = textDic[.refreshSuccess]
            imageView.image = UIImage(named: "success", in: Bundle(for: DefaultRefreshHeader.self), compatibleWith: nil)
        case .failure:
            textLabel.text = textDic[.refreshFailure]
            imageView.image = UIImage(named: "failure", in: Bundle(for: DefaultRefreshHeader.self), compatibleWith: nil)
        case .none:
            textLabel.text = textDic[.pullToRefresh]
            imageView.image = UIImage(named: "arrow_down", in: Bundle(for: DefaultRefreshHeader.self), compatibleWith: nil)
        }
        if imageRenderingWithTintColor{
            imageView.image = imageView.image?.withRenderingMode(.alwaysTemplate)
        }
    }
    open func didCompleteHideAnimation(_ result:RefreshResult) {
        textLabel.text = textDic[.pullToRefresh]
        self.isHidden = true
        imageView.image = UIImage(named: "arrow_down", in: Bundle(for: DefaultRefreshHeader.self), compatibleWith: nil)
        if imageRenderingWithTintColor{
            imageView.image = imageView.image?.withRenderingMode(.alwaysTemplate)
        }
    }
    open func didBeginRefreshingState() {
        self.isHidden = false
        textLabel.text = textDic[.refreshing]
        spinner.startAnimating()
        imageView.isHidden = true
    }
    
    override open var tintColor: UIColor!{
        didSet{
            textLabel.textColor = tintColor
            spinner.color = tintColor
            imageView.tintColor = tintColor
        }
    }
}

open class RefreshHeaderContainer:UIView{
    // MARK: - Propertys -
    var refreshAction:(()->())?
    var attachedScrollView:UIScrollView!
    var originalInset:UIEdgeInsets?
    var durationOfEndRefreshing = 0.4
    weak var delegate:RefreshableHeader?
    fileprivate var currentResult:RefreshResult = .none
    fileprivate var _state:RefreshHeaderState = .idle
    fileprivate var insetTDelta:CGFloat = 0.0
    fileprivate var delayTimer:Timer?
    fileprivate var state:RefreshHeaderState{
        get{
            return _state
        }
        set{
            guard newValue != _state else{
                return
            }
            self.delegate?.stateDidChanged?(_state,newState: newValue)
            let oldValue = _state
            _state =  newValue
            switch newValue {
            case .idle:
                guard oldValue == .refreshing else{
                    return
                }
                UIView.animate(withDuration: durationOfEndRefreshing, animations: {
                    var oldInset = self.attachedScrollView.contentInset
                    oldInset.top = oldInset.top + self.insetTDelta
                    self.attachedScrollView.contentInset = oldInset
                    }, completion: { (finished) in
                        self.delegate?.didCompleteHideAnimation(self.currentResult)
                })
            case .refreshing:
                DispatchQueue.main.async(execute: {
                    var insetHeight:CGFloat! = self.delegate?.heightForRefreshingState?()
                    if insetHeight == nil{
                        insetHeight = self.delegate?.heightForHeader()
                    }
                    var fireHeight:CGFloat! = self.delegate?.heightForFireRefreshing?()
                    if fireHeight == nil{
                        fireHeight = self.delegate?.heightForHeader()
                    }
                    let offSetY = self.attachedScrollView.contentOffset.y
                    let topShowOffsetY = -1.0 * self.originalInset!.top
                    let normal2pullingOffsetY = topShowOffsetY - fireHeight
                    let currentOffset = self.attachedScrollView.contentOffset
                    UIView.animate(withDuration: 0.4, animations: {
                        let top = (self.originalInset?.top)! + insetHeight
                        var oldInset = self.attachedScrollView.contentInset
                        oldInset.top = top
                        self.attachedScrollView.contentInset = oldInset
                        if offSetY > normal2pullingOffsetY{ //手动触发
                            self.attachedScrollView.contentOffset = CGPoint(x: 0, y: -1.0 * top)
                        }else{//release，防止跳动
                            self.attachedScrollView.contentOffset = currentOffset
                        }
                        }, completion: { (finsihed) in
                            self.refreshAction?()
                    })
                    self.delegate?.percentUpdateDuringScrolling?(1.0)
                    self.delegate?.didBeginRefreshingState()
                })
            default:
                break
            }
        }
    }
    // MARK: - Init -
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    func commonInit(){
        self.isUserInteractionEnabled = true
        self.backgroundColor = UIColor.clear
        self.autoresizingMask = .flexibleWidth
    }
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Life circle -
    open override func draw(_ rect: CGRect) {
        super.draw(rect)
        if self.state == .willRefresh {
            self.state = .refreshing
        }
    }
    open override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        guard newSuperview is UIScrollView else{
            return;
        }
        attachedScrollView = newSuperview as? UIScrollView
        attachedScrollView.alwaysBounceVertical = true
        originalInset = attachedScrollView?.contentInset
        addObservers()
    }
    deinit{
        clearTimer()
        removeObservers()
    }
    // MARK: - Private -
    fileprivate func addObservers(){
        attachedScrollView?.addObserver(self, forKeyPath:PullToRefreshKitConst.KPathOffSet, options: [.old,.new], context: nil)
    }
    fileprivate func removeObservers(){
        attachedScrollView?.removeObserver(self, forKeyPath: PullToRefreshKitConst.KPathOffSet,context: nil)
    }
    func handleScrollOffSetChange(_ change: [NSKeyValueChangeKey : Any]?){
        var insetHeight:CGFloat! = self.delegate?.heightForRefreshingState?()
        if insetHeight == nil {
            insetHeight = self.delegate?.heightForHeader()
        }
        var fireHeight:CGFloat! = self.delegate?.heightForFireRefreshing?()
        if fireHeight == nil{
            fireHeight = self.delegate?.heightForHeader()
        }
        if state == .refreshing {
            guard self.window != nil else{
                return
            }
            let offset = attachedScrollView.contentOffset
            let inset = originalInset!
            var insetT = -1 * offset.y > inset.top ? (-1 * offset.y):inset.top
            insetT = insetT > insetHeight + inset.top ? insetHeight + inset.top:insetT
            var oldInset = attachedScrollView.contentInset
            oldInset.top = insetT
            attachedScrollView.contentInset = oldInset
            insetTDelta = inset.top - insetT
            return;
        }
        
        originalInset =  attachedScrollView.contentInset
        let offSetY = attachedScrollView.contentOffset.y
        let topShowOffsetY = -1.0 * originalInset!.top
        guard offSetY <= topShowOffsetY else{
            return
        }
        let normal2pullingOffsetY = topShowOffsetY - fireHeight
        if attachedScrollView.isDragging {
            if state == .idle && offSetY < normal2pullingOffsetY {
                self.state = .pulling
            }else if state == .pulling && offSetY >= normal2pullingOffsetY{
                state = .idle
            }
        }else if state == .pulling{
            beginRefreshing()
            return
        }
        let percent = (topShowOffsetY - offSetY)/fireHeight
        //防止在结束刷新的时候，percent的跳跃
        if let oldOffset = (change?[NSKeyValueChangeKey.oldKey] as AnyObject).cgPointValue{
            let oldPercent = (topShowOffsetY - oldOffset.y)/fireHeight
            if oldPercent >= 1.0 && percent == 0.0{
                return
            }else{
                self.delegate?.percentUpdateDuringScrolling?(percent)
            }
        }else{
            self.delegate?.percentUpdateDuringScrolling?(percent)
        }
    }
    // MARK: - KVO -
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard self.isUserInteractionEnabled else{
            return;
        }
        if keyPath == PullToRefreshKitConst.KPathOffSet {
            handleScrollOffSetChange(change)
        }
    }
    // MARK: - API -
    func beginRefreshing(){
        if self.window != nil {
            self.state = .refreshing
        }else{
            if state != .refreshing{
                self.state = .willRefresh
            }
        }
    }
    @objc func updateStateToIdea(){
        self.state = .idle
        clearTimer()
    }
    func endRefreshing(_ result:RefreshResult,delay:TimeInterval = 0.0){
        self.delegate?.didBeginHideAnimation(result)
        self.delayTimer = Timer(timeInterval: delay, target: self, selector: #selector(RefreshHeaderContainer.updateStateToIdea), userInfo: nil, repeats: false)
        #if swift(>=4.2)
        RunLoop.main.add(self.delayTimer!, forMode: RunLoop.Mode.common)
        #else
        RunLoop.main.add(self.delayTimer!, forMode: RunLoopMode.commonModes)
        #endif
    }
    func clearTimer(){
        if self.delayTimer != nil{
            self.delayTimer?.invalidate()
            self.delayTimer = nil
        }
    }
}



