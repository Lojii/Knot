//
//  BaseViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class BaseViewController: UIViewController {

    /// 自定义导航栏
    open lazy var navBar: NavBar = {
        let nav = NavBar()
        nav.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: NAVGATIONBARHEIGHT)
        nav.backgroundColor = UIColor.clear
        return nav
    }()
    /// 右边第一个按钮
    open lazy var rightBtn: UIButton = {
        let btn = UIButton()
        btn.frame = CGRect.zero
        btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: 0)
        btn.titleLabel?.font = Font16
        btn.addTarget(self, action: #selector(BaseViewController.rightBtnClick), for: UIControl.Event.touchUpInside)
        return btn
    }()
    /// 右边第二个按钮
    open lazy var rightBtnTwo: UIButton = {
        let btn = UIButton()
        btn.frame = CGRect.zero
        btn.adjustsImageWhenHighlighted = false
        btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: 0)
        btn.setTitleColor(UIColor.black, for: .normal)
        btn.titleLabel?.font = Font16
        btn.addTarget(self, action: #selector(BaseViewController.rightBtnTwoClick), for: UIControl.Event.touchUpInside)
        return btn
    }()
    
    /// 标题
    open var navTitle = "" {
        didSet{
            navBar.titleLable.text = navTitle
        }
    }
    open var navTitleColor = UIColor.black {
        didSet{
            navBar.titleLable.textColor = navTitleColor
        }
    }
    open var navBgColor = UIColor.white {
        didSet{
            navBar.backgroundColor = navBgColor
        }
    }
    // 返回按钮
    open lazy var backBtn: UIButton = {
        let btn = UIButton()
        btn.frame = CGRect.zero
        btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: 0)
        btn.addTarget(self, action: #selector(BaseViewController.backBtnclick), for: .touchUpInside)
        btn.setImage(UIImage(named: "back1"), for: .normal)//btn_back
        return btn
    }()
    
    var _showLeftBtn:Bool = false
    var showLeftBtn:Bool{
        set{
            _showLeftBtn = newValue
            backBtn.isHidden = !_showLeftBtn
        }
        get{
            return _showLeftBtn
        }
    }
    
    /// 设置右边按钮的宽度，默认宽度64
    open var rightBtnWidthConstraint = NSLayoutConstraint()
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = ColorF
        self.automaticallyAdjustsScrollViewInsets = false
        self.navigationController?.navigationBar.isHidden = true
        self.navigationController?.navigationBar.isTranslucent = false
        
        setupNav()
        setupLayout()
    }
    func setupLayout() {
        let titleY: CGFloat = UIDevice.isX() == true ? 40:20
        
        self.navBar.translatesAutoresizingMaskIntoConstraints = false
        self.rightBtnTwo.translatesAutoresizingMaskIntoConstraints = false
        self.rightBtn.translatesAutoresizingMaskIntoConstraints = false
        self.backBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // 导航栏
        self.navBar.addConstraint(NSLayoutConstraint.init(item: self.navBar, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: NAVGATIONBARHEIGHT))
        self.view.addConstraints([
            NSLayoutConstraint.init(item: self.navBar, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.view, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.navBar, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.view, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.navBar, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.view, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0)
            ])
        // 右边的按钮
        self.rightBtnWidthConstraint = NSLayoutConstraint.init(item: self.rightBtn, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 64)
        self.rightBtn.addConstraint(NSLayoutConstraint.init(item: self.rightBtn, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 44))
        self.rightBtn.addConstraint(self.rightBtnWidthConstraint)
        self.navBar.addConstraints([
            NSLayoutConstraint.init(item: self.rightBtn, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.navBar, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: titleY),
            NSLayoutConstraint.init(item: self.rightBtn, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.navBar, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0)
            ])
        
        // 返回按钮
        self.backBtn.addConstraint(NSLayoutConstraint.init(item: self.backBtn, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 44))
        self.backBtn.addConstraint(NSLayoutConstraint.init(item: self.backBtn, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 44))
        self.navBar.addConstraints([
            NSLayoutConstraint.init(item: self.backBtn, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.navBar, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: titleY),
            NSLayoutConstraint.init(item: self.backBtn, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.navBar, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0)
            ])
        
        
        // rightBtnTwo
        self.rightBtnTwo.addConstraint(NSLayoutConstraint.init(item: self.rightBtnTwo, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 44))
        self.rightBtnTwo.addConstraint(NSLayoutConstraint.init(item: self.rightBtnTwo, attribute: NSLayoutConstraint.Attribute.width, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 64))
        self.navBar.addConstraints([
            NSLayoutConstraint.init(item: self.rightBtnTwo, attribute: NSLayoutConstraint.Attribute.centerY, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.rightBtn, attribute: NSLayoutConstraint.Attribute.centerY, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.rightBtnTwo, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self.rightBtn, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0)
            ])
    }
    
    fileprivate func setupNav(){
        
        // 添加导航栏
        self.view.addSubview(self.navBar)
        
        // 右边按钮
        self.navBar.addSubview(self.rightBtn)
        self.navBar.addSubview(self.rightBtnTwo)
        self.navBar.addSubview(self.backBtn)
        
        // 多层push才显示返回按钮
        if self.navigationController != nil {
            if ((self.navigationController?.children.count)!>1){
                self.backBtn.isHidden = false
            } else {
                self.backBtn.isHidden = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) {
            self.view.bringSubviewToFront(self.navBar)
        }
    }
    
    @objc open func rightBtnTwoClick() {
        
    }
    
    @objc open func rightBtnClick(){
        
    }
    @objc open func backBtnclick(){
        let VCArr = self.navigationController?.viewControllers
        if VCArr == nil {
            self.dismiss(animated: true, completion: nil)
            return
        }
        if VCArr!.count > 1 {
            self.navigationController!.popViewController(animated: true)
        } else {
            self.dismiss(animated: true, completion: nil)
        }
    }
    //状态栏颜色默认为黑色
    override open var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
    
    //点击空白处, 回收键盘
    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        self.view.endEditing(true)
    }

}
