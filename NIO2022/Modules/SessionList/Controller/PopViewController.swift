//
//  PopViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/1.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class PopViewController: UIViewController,PopupContentViewController {

    var closeHandler: (() -> Void)?
    var itemClickHandler: ((Int) -> Void)?
    var titles:[String]
    
    let cornerRadius:CGFloat = 12
    var viewHeight:CGFloat = 0
    let spacing:CGFloat = 8
    let viewWidth:CGFloat = SCREENWIDTH - 8 * 2//LRSpacing
    let titleHeight:CGFloat = 50  // 57
    
    var cancelBtn:UIButton = UIButton()
    
    init(titles:[String]) {
        self.titles = titles
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
    }
    
    static func show(titles:[String], viewController:UIViewController, itemClickHandler: ((Int) -> Void)?){
        let popup = PopupController.create(viewController)
            .customize(
                [
                    .layout(.bottom),
                    .animation(.slideUp),
                    .backgroundStyle(.blackFilter(alpha: 0.5)),
                    .dismissWhenTaps(true),
                    .scrollable(true)
                ]
        )
        let container = PopViewController(titles: titles)
        container.closeHandler = { popup.dismiss() }
        container.itemClickHandler = itemClickHandler
        popup.show(container)
    }
    
    func setupUI(){
        var offY:CGFloat = 0
        let topView = UIView()
        topView.backgroundColor = ColorF
        topView.layer.cornerRadius = cornerRadius
        topView.clipsToBounds = true
        for i in 0..<titles.count {
            let btn = setButton(title: titles[i], y: offY, action: #selector(titleDidClick(sender:)))
            btn.tag = i
            offY = btn.frame.maxY + 1
            topView.addSubview(btn)
        }
        topView.frame = CGRect(x: spacing, y: 0, width: viewWidth, height: offY-1)
        view.addSubview(topView)
        
        let bottomView = UIView()
        bottomView.backgroundColor = ColorR
        bottomView.layer.cornerRadius = cornerRadius
        bottomView.clipsToBounds = true
        
        cancelBtn = setButton(title: "Cancel".localized, y: 0, action: #selector(cancel))
        cancelBtn.clipsToBounds = true
        cancelBtn.layer.cornerRadius = 10
        bottomView.addSubview(cancelBtn)
        bottomView.frame = CGRect(x: spacing, y: topView.frame.maxY + spacing, width: viewWidth, height: cancelBtn.frame.height)
        view.addSubview(bottomView)
        
        viewHeight = bottomView.frame.maxY + spacing + XBOTTOMHEIGHT
    }
    
    func setButton(title:String,y:CGFloat, action: Selector) -> UIButton{
        let btn = UIButton(frame: CGRect(x: 0, y: y, width: viewWidth, height: titleHeight))
        btn.setTitleColor(ColorA, for: .normal)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(ColorB, for: .highlighted)
        btn.setBackgroundImage(UIImage.renderImageWithColor(ColorF, size: CGSize(width: SCREENWIDTH, height: 100)), for: .highlighted)
        btn.backgroundColor = .white
        btn.titleLabel?.font = Font18
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }
    
    @objc func titleDidClick(sender:UIButton){
        if itemClickHandler != nil {
            itemClickHandler!(sender.tag)
        }
        closeHandler?()
    }
    
    @objc func cancel(){
        closeHandler?()
    }
    
    func sizeForPopup(_ popupController: PopupController, size: CGSize, showingKeyboard: Bool) -> CGSize {
        return CGSize(width: SCREENWIDTH, height: viewHeight)
    }
}
