//
//  IDDialogInputView.swift
//  IDDialogInputView
//
//  Created by darren on 2018/8/30.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit

typealias IDDialogInputViewClouse = (String)->()

class IDDialogInputView: UIView {

    lazy var msgLabel: UILabel = {
        let title = UILabel.init(frame: CGRect.zero)
        title.textAlignment = .center
        title.numberOfLines = 0
        title.font = UIFont.systemFont(ofSize: 14)
        return title
    }()
    lazy var textView: IDDialogTextView = {
        let text = IDDialogTextView.init(frame: CGRect.zero)
        text.placehoder = "请输入..."
        text.backgroundColor = UIColor.white
        text.layer.cornerRadius = 5
        text.layer.borderWidth = 1
        text.layer.borderColor = UIColor.groupTableViewBackground.cgColor
        return text
    }()
    lazy var leftBtn: UIButton = {
        let btn = UIButton.init(type: UIButton.ButtonType.system)
        btn.setTitleColor(RGBAColor(23, 32, 46, 1), for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        btn.addTarget(self, action: #selector(clickLeftbtn), for: .touchUpInside)
        return btn
    }()
    lazy var rightBtn: UIButton = {
        let btn = UIButton.init(type: UIButton.ButtonType.system)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        btn.addTarget(self, action: #selector(clickRightbtn), for: .touchUpInside)
        return btn
    }()
    lazy var lineViewRow: UIView = {
        let line = UIView.init(frame: CGRect.zero)
        line.backgroundColor = UIColor.groupTableViewBackground
        return line
    }()
    lazy var lineView: UIView = {
        let line = UIView.init(frame: CGRect.zero)
        line.backgroundColor = UIColor.groupTableViewBackground
        return line
    }()
    lazy var bottomView: UIView = {
        let bottom = UIView.init(frame: CGRect.zero)
        bottom.backgroundColor = UIColor.clear
        return bottom
    }()
    
    open var msg: String? {
        get { return self.msgLabel.text }
        set { self.msgLabel.text = newValue }
    }
    open var leftActionTitle: String? {
        get { return self.leftBtn.currentTitle }
        set { self.leftBtn.setTitle(newValue, for: .normal)  }
    }
    open var rightActionTitle: String? {
        get { return self.rightBtn.currentTitle }
        set { self.rightBtn.setTitle(newValue, for: .normal)  }
    }
    
    open var leftHandler: IDDialogInputViewClouse?
    open var rightHandler: IDDialogInputViewClouse?
    
    var keyBoardHeight: CGFloat = 0
    
    var superWidth = KScreenWidth
    var superHeight = KScreenHeight
    var textHeight: CGFloat = 36
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.addGestureRecognizer(UITapGestureRecognizer.init(target: self, action: #selector(clickTitle)))

        initView()
        initEventHendle()
    }
    func fitFont() {
        if KScreenWidth > 375 && UIDevice.current.orientation == .portrait {
            self.msgLabel.font = UIFont.systemFont(ofSize: 16)
            self.rightBtn.titleLabel?.font = UIFont.systemFont(ofSize: 17)
            self.leftBtn.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        } else {
            self.msgLabel.font = UIFont.systemFont(ofSize: 14)
            self.rightBtn.titleLabel?.font = UIFont.systemFont(ofSize: 15)
            self.leftBtn.titleLabel?.font = UIFont.systemFont(ofSize: 15)
        }
    }

    @objc func clickTitle() {
        UIApplication.shared.keyWindow?.endEditing(true)
    }
    func initEventHendle() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(aNotification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(aNotification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        ScreenTools.share.screenClouse = { [weak self] (orientation) in
            self?.setNeedsLayout()
        }
        
        self.textView.textChangeClouse = {[weak self] (textHeight) in
            
            self?.textHeight = textHeight
            self?.setNeedsLayout()
            self?.textView.isScrollEnabled = false
        }
    }
    @objc func keyboardWillShow(aNotification: Notification) {
        let userInfo = aNotification.userInfo
        guard let info = userInfo else {
            return
        }
        let aValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        let keyboardRect = aValue?.cgRectValue
        let height = keyboardRect?.size.height
        self.keyBoardHeight = height ?? 0
        self.setNeedsLayout()
    }
    @objc func keyboardWillHide(aNotification: Notification) {
        self.keyBoardHeight = 0
        self.setNeedsLayout()
    }
    func initView() {
        self.layer.cornerRadius = 8
        self.backgroundColor = UIColor.white
        self.addSubview(self.textView)
        self.addSubview(self.msgLabel)
        self.addSubview(self.lineViewRow)
        self.addSubview(self.bottomView)
        self.bottomView.addSubview(self.leftBtn)
        self.bottomView.addSubview(self.rightBtn)
        self.bottomView.addSubview(self.lineView)
    }
    
    @objc func clickLeftbtn() {
        IDDialogManager.share.id_resetInputProps()
        if self.leftHandler != nil {
            self.leftHandler!(self.dealText())
        }
    }
    @objc func clickRightbtn() {
        IDDialogManager.share.id_resetInputProps()
        if self.rightHandler != nil {
            self.rightHandler!(self.dealText())
        }
    }
    // 如果出现3.的情况，就把小数点去掉
    func dealText() -> String {
        var tempText = ""
        let arr = self.textView.text.components(separatedBy: ".")
        if arr.count == 2 {
            if arr.last == nil || arr.last == "" {
                tempText = arr.first ?? ""
            }
        } else {
            tempText = self.textView.text
        }
        return tempText
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.fitFont()
        
        self.superWidth = KScreenWidth
        self.superHeight = KScreenHeight
        
        let constraintSize = CGSize(
            width: dialogWidth - 20,
            height: self.superHeight - 150
        )
        var msgSize = self.msgLabel.sizeThatFits(constraintSize)
        if msgSize.height > constraintSize.height  {
            msgSize.height = constraintSize.height
        }
        self.msgLabel.preferredMaxLayoutWidth = dialogWidth - 20
        
        msgSize.height > 0 ? (self.msgLabel.frame = CGRect.init(x: 10, y: 20, width: dialogWidth-20, height: msgSize.height)):(self.msgLabel.frame = CGRect.zero)
        self.textView.frame = CGRect.init(x: 10, y: self.msgLabel.frame.maxY + 20, width: dialogWidth-20, height: textHeight)
        self.lineViewRow.frame = CGRect.init(x: 0, y: self.textView.frame.maxY + 20, width: dialogWidth, height: 1)
        self.bottomView.frame = CGRect.init(x: 0, y: self.lineViewRow.frame.maxY, width: dialogWidth, height: 50)
        if self.leftActionTitle == nil || self.leftActionTitle?.count == 0 {
            self.leftBtn.frame = CGRect.zero
            self.lineView.frame = CGRect.zero
            self.rightBtn.frame = self.bottomView.bounds
            
            self.frame = CGRect.init(x: 0.5*(superWidth - dialogWidth), y: 0.5*(superHeight - (self.bottomView.frame.maxY)), width: dialogWidth, height: self.bottomView.frame.maxY)
            self.rightBtn.setTitleColor(IDDialogManager.share.mainColor, for: .normal)
            return
        }
        if self.rightActionTitle == nil || self.rightActionTitle?.count == 0 {
            self.rightBtn.frame = CGRect.zero
            self.lineView.frame = CGRect.zero
            self.leftBtn.frame = self.bottomView.bounds
            
            self.frame = CGRect.init(x: 0.5*(superWidth - dialogWidth), y: 0.5*(superHeight - (self.bottomView.frame.maxY)), width: dialogWidth, height: self.bottomView.frame.maxY)
            self.leftBtn.setTitleColor(IDDialogManager.share.mainColor, for: .normal)
            return
        }
        if self.rightActionTitle != nil && self.leftActionTitle != nil {
            self.leftBtn.frame = CGRect.init(x: 0, y: 0, width: dialogWidth*0.5-0.5, height: self.bottomView.frame.height)
            self.rightBtn.frame = CGRect.init(x: dialogWidth*0.5+0.5, y: 0, width: dialogWidth*0.5-0.5, height: self.bottomView.frame.height)
            self.lineView.frame = CGRect.init(x: dialogWidth*0.5-0.5, y: 0, width: 1, height: self.bottomView.frame.height)
        }
        
        if self.keyBoardHeight > 0 {
            self.frame = CGRect.init(x: 0.5*(superWidth - dialogWidth), y: superHeight-self.keyBoardHeight-self.bottomView.frame.maxY, width: dialogWidth, height: self.bottomView.frame.maxY)
        } else {
            self.frame = CGRect.init(x: 0.5*(superWidth - dialogWidth), y: 0.5*(superHeight - (self.bottomView.frame.maxY)), width: dialogWidth, height: self.bottomView.frame.maxY)
        }
        self.rightBtn.setTitleColor(IDDialogManager.share.mainColor, for: .normal)
    }
}
