//
//  RuleTextViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/11.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class RuleTextViewController: BaseViewController,PopupContentViewController,UITextViewDelegate {
    
    var closeHandler: (() -> Void)?
    
    var rule:Rule
    
    var textView:UITextView
    var isChanged:Bool = false
    
    init(rule:Rule) {
        self.rule = rule
        self.textView = UITextView()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navTitle = rule.name
        showLeftBtn = false
        setupUI()
    }
    
    func setupUI(){
        rightBtn.setTitle("Done".localized, for: .normal)
        rightBtn.setTitleColor(ColorM, for: .normal)
        let cancelBtn = UIButton()
        cancelBtn.setTitle("Cancel".localized, for: .normal)
        cancelBtn.setTitleColor(ColorM, for: .normal)
        cancelBtn.addTarget(self, action: #selector(cancelBtnclick), for: .touchUpInside)
        cancelBtn.titleLabel?.font = Font16
        navBar.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { (m) in
            m.left.equalToSuperview()
            m.centerY.equalTo(rightBtn)
            m.width.height.equalTo(rightBtn)
        }
        view.addSubview(textView)
        textView.snp.makeConstraints { (m) in
            m.top.equalToSuperview().offset(NAVGATIONBARHEIGHT)
            m.left.right.bottom.equalToSuperview()
        }
        textView.text = rule.config
        textView.font = Font14
        textView.textColor = ColorB
        textView.delegate = self
    }
    
    override func rightBtnClick() {
        rule.config = textView.text
        closeHandler?()
        dismiss(animated: true, completion: nil)
    }
    
    @objc func cancelBtnclick() {
        if isChanged {
            IDDialog.id_show(title: "The text has been modified. Whether to save or not".localized, msg: nil, countDownNumber: nil, leftActionTitle: "Cancel".localized, rightActionTitle: "Ok".localized, leftHandler: {
                self.closeHandler?()
                self.dismiss(animated: true, completion: nil)
            }) {
                self.rule.config = self.textView.text
                self.closeHandler?()
                self.dismiss(animated: true, completion: nil)
            }
        }else{
            closeHandler?()
            dismiss(animated: true, completion: nil)
        }
        
    }
    
    func sizeForPopup(_ popupController: PopupController, size: CGSize, showingKeyboard: Bool) -> CGSize {
        return CGSize(width: SCREENWIDTH, height: SCREENHEIGHT)
    }
    
    func textViewDidChange(_ textView: UITextView) {
        isChanged = true
    }
    
}
