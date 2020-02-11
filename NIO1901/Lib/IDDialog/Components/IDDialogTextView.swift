//
//  CLTextView.swift
//  CLDialog
//
//  Created by darren on 2018/8/30.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit

typealias IDDialogTextViewTextDidChangeClouse = (CGFloat) -> ()
class IDDialogTextView: UITextView {
    var placehoder: String? {
        didSet{
            // 设置文字
            self.placehoderLabel?.text = placehoder
            // 重新计算子控件的fame
            self.setNeedsLayout()
        }
    }
    var placehoderColor: UIColor? {
        didSet{
            // 设置颜色
            self.placehoderLabel?.textColor = placehoderColor
        }
    }
    var placehoderLabel: UILabel?
    
    var textChangeClouse: IDDialogTextViewTextDidChangeClouse?
    
    /// 最多允许输入多少个字符
    var maxLength: Int?
    /// 只允许输入数字和小数点
    var onlyNumberAndPoint: Bool?
    /// 设置小数点位数
    var pointLength: Int?
    /// 只允许输入数字
    var onlyNumber: Bool?
    /// 禁止输入表情符号emoji
    var allowEmoji: Bool?
    /// 正则表达式
    var predicateString: String?
    
    // 记录textview的临时值
    var tempText: String?
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        
        self.setupTextView()
    }
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setupTextView()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setupTextView()
    }
    
    func setupTextView(){
        self.backgroundColor = UIColor.clear
        
        // 添加一个显示提醒文字的label（显示占位文字的label）
        let placehoderLabel = UILabel()
        placehoderLabel.numberOfLines = 0
        placehoderLabel.backgroundColor = UIColor.clear
        placehoderLabel.font = UIFont.systemFont(ofSize: 14)
        self.addSubview(placehoderLabel)
        self.placehoderLabel = placehoderLabel
        
        // 设置默认的占位文字颜色
        self.placehoderColor = UIColor.init(red: 120/255, green: 120/255, blue: 120/255, alpha: 1)
        
        // 设置默认的字体
        self.font = UIFont.systemFont(ofSize: 14)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.textDidChange(notic:)), name: UITextView.textDidChangeNotification, object: self)
        
        self.maxLength = IDDialogManager.share.maxLength
        self.onlyNumberAndPoint = IDDialogManager.share.onlyNumberAndPoint
        self.onlyNumber = IDDialogManager.share.onlyNumber
        self.allowEmoji = IDDialogManager.share.allowEmoji
        self.pointLength = IDDialogManager.share.pointLength
        self.predicateString = IDDialogManager.share.predicateString
    }
    //MARK - 监听文字改变
    @objc func textDidChange(notic: Notification){
        
        // 只允许输入数字和小数点
        if self.onlyNumberAndPoint == true {
            self.dealOnlyNumberAndPoint()
        }
        
        // 限制长度
        if self.maxLength != nil && self.maxLength! > 0 {
            if (self.text.count) > (self.maxLength)! {
                let subString = self.text.subString(to: (self.maxLength)!)
                self.text = subString
            }
        }
        
        // 数字
        if self.onlyNumber == true {
            for i in (self.text)! {
                if "0123456789".contains(i)==false {
                    let index = self.text.firstIndex(of: i)
                    if index != nil {
                        self.text.remove(at: index!)
                    }
                }
            }
        }
        
        // 表情符号
        if self.allowEmoji == false {
            for i in (self.text)! {
                let resultStr = String.init(i)
                if (resultStr as NSString).length > 1 { // 表情的长度是2，字符个数是1，可以过滤表情
                    let index = self.text.firstIndex(of: i)
                    if index != nil {
                        self.text.remove(at: index!)
                    }
                }
            }
        }
        
        // 自定义正则
        if self.predicateString != nil {
            self.dealPredicate()
        }
        
        self.tempText = self.text
        
        self.placehoderLabel?.isHidden = (self.text.count != 0)
        let constraintSize = CGSize(
            width: dialogWidth - 20,
            height: CGFloat.greatestFiniteMagnitude
        )
        let msgSize = self.sizeThatFits(constraintSize)
        
        if self.textChangeClouse != nil {
            self.textChangeClouse!(msgSize.height)
        }
    }
    
    func dealPredicate() {
        if (self.tempText?.count ?? 0) > self.text.count {  // 回退的时候可能会出现tempText为1234，textview=123的情况
            self.tempText = self.text
        }
        // 用户输入的，比如textview=123 用户再输入4，那么newInputStr = 4
        var newInputStr = self.text.subString(from: self.tempText?.count ?? 0)
        
        let predicate = NSPredicate.init(format: "SELF MATCHES %@", (self.predicateString ?? ""))
        let isRight = predicate.evaluate(with: newInputStr)
        if !isRight {
            newInputStr = ""
        }
        self.text = (self.tempText ?? "") + newInputStr
    }
    
    func dealOnlyNumberAndPoint() {
        if (self.tempText?.count ?? 0) > self.text.count {  // 回退的时候可能会出现tempText为1234，textview=123的情况
            self.tempText = self.text
        }
        // 用户输入的，比如textview=123 用户再输入4，那么newInputStr = 4
        var newInputStr = self.text.subString(from: self.tempText?.count ?? 0)
        
        //1.只允许输入数字和小数点
        for i in (self.tempText ?? "") {
            if "0123456789.".contains(i)==false {
                let index = self.tempText?.firstIndex(of: i)
                if index != nil {
                    self.tempText?.remove(at: index!)
                }
            }
        }
        for i in newInputStr {
            if "0123456789.".contains(i)==false {
                let index = newInputStr.firstIndex(of: i)
                if index != nil {
                    newInputStr.remove(at: index!)
                }
            }
        }
        
        // 2.限制小数点只能输入1个
        if (self.tempText?.contains(".") ?? false) {
            if newInputStr.contains(".") {
                let index = newInputStr.firstIndex(of: ".")
                if index != nil {
                    newInputStr.remove(at: index!)
                }
            }
        }
        
        // 3.限制小数点位数
        if self.pointLength != nil && self.pointLength! > 0 {
            let arr = self.tempText?.components(separatedBy: ".")
            if arr?.count == 2 { // 有小数点
                // 小数点位数
                let pointConut = arr?.last?.count ?? 0
                if pointConut >= self.pointLength! {
                    self.tempText = (arr?.first ?? "") + "." + (arr?.last?.subString(to: self.pointLength!) ?? "")
                    newInputStr = ""
                } else {
                    let count = (arr?.last?.count ?? 0) + newInputStr.count
                    if count > self.pointLength! {
                        let newCount = count - self.pointLength!
                        newInputStr = newInputStr.subString(to: newCount)
                    }
                }
            }
        }
        
        // 4.小数点不能放在第一位
        if self.tempText == nil && newInputStr == "." {
            newInputStr = ""
        }
        
        self.text = (self.tempText ?? "") + newInputStr
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.placehoderLabel?.frame = CGRect.init(x: 5, y: 0, width: self.frame.width-10, height: 35)
        self.placehoderLabel?.isHidden = (self.text.count != 0)
    }
}
