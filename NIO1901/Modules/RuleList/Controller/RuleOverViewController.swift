//
//  RuleOverViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class RuleOverViewController: UIViewController {
    
    var rule:Rule
    
    var nameItem = RuleItemView()
    var numbItem = RuleItemView()
    var modeItem = RuleItemView()
    var ignoreItem = RuleItemView()
    var textEditItem = RuleItemView()
    var noteItem = RuleItemView()
    var shareItem = RuleItemView()
    
    lazy var scrollView: UIScrollView = {
        let scrollViewFrame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let scrollView = UIScrollView(frame: scrollViewFrame)
        scrollView.backgroundColor = ColorF
        return scrollView
    }()
    
    init(rule:Rule) {
        self.rule = rule
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(currentRuleDidChange(noti:)), name: CurrentRuleDidChange, object: nil)
        setupUI()
    }
    
    func setupUI(){
        view.addSubview(scrollView)
        //
        var offY:CGFloat = 0
        nameItem = RuleItemView(title: "Name".localized, rule.name, nil, false, describe: nil, type: .Field, false, "Enter a name".localized)
        nameItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: nameItem.itemHeight)
        offY = nameItem.frame.maxY
        nameItem.textValueChangeHandle = { name in
            self.rule.name = name
        }
        scrollView.addSubview(nameItem)
        
        numbItem = RuleItemView(title: nil, "Number of rules".localized, "0", false, describe: nil, type: .Label, false)
        numbItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: numbItem.itemHeight)
        offY = numbItem.frame.maxY
        numbItem.contentDidClickHandle = {
            
        }
        scrollView.addSubview(numbItem)
        
        modeItem = RuleItemView(title: nil, "Currently in blacklist mode".localized, "Currently in whitelist mode".localized, rule.defaultStrategy == .DIRECT, describe: "Blacklist mode describe".localized, type: .Switch)
        modeItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: modeItem.itemHeight)
        offY = modeItem.frame.maxY
        modeItem.boolValueChangeHandle = { isOpen in
            self.rule.defaultStrategy = isOpen ? .DIRECT : .COPY
        }
        scrollView.addSubview(modeItem)
        
        ignoreItem = RuleItemView(title: nil, "Suggest to ignore".localized, nil, rule.defaultBlacklistEnable, describe: "These domains require specific certificates or error analysis requests that are recommended to be ignored, for example apple.com".localized, type: .Switch)
        ignoreItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: ignoreItem.itemHeight)
        offY = ignoreItem.frame.maxY
        ignoreItem.boolValueChangeHandle = { isOpen in
            self.rule.defaultBlacklistEnable = isOpen
        }
        ignoreItem.contentDidClickHandle = {
            let popup = PopupController.create(self.parent?.parent ?? self)
                .customize(
                    [
                        .layout(.bottom),
                        .animation(.slideUp),
                        .backgroundStyle(.blackFilter(alpha: 0.5)),
                        .dismissWhenTaps(true),
                        .scrollable(true)
                    ]
            )
            let blackItems = Rule().defaulBlacklistRuleItems
            let vc = BlackRuleListViewController()
            vc.closeHandler = { popup.dismiss() }
            vc.items = blackItems
            popup.show(vc)
        }
        scrollView.addSubview(ignoreItem)
        
        textEditItem = RuleItemView(title: nil, "Text editing mode".localized, nil, true, describe: nil, type: .Label, true)
        textEditItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: textEditItem.itemHeight)
        offY = textEditItem.frame.maxY
        textEditItem.contentDidClickHandle = {
            let container = RuleTextViewController(rule: self.rule)
            container.modalPresentationStyle = .fullScreen
            self.present(container, animated: true, completion: nil)
        }
        scrollView.addSubview(textEditItem)
        
        noteItem = RuleItemView(title: "Remark".localized, "", rule.note, false, describe: nil, type: .Field, false,  "输入备注信息")
        noteItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: noteItem.itemHeight)
        offY = noteItem.frame.maxY
        noteItem.textValueChangeHandle = { note in
            self.rule.note = note
        }
        scrollView.addSubview(noteItem)
        
        shareItem = RuleItemView(title: nil, "Share".localized, nil, true, describe: nil, type: .Label, true)
        shareItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: shareItem.itemHeight)
        offY = shareItem.frame.maxY
        shareItem.contentDidClickHandle = {
            VisualActivityViewController.share(text: self.rule.config, on: self.parent?.parent ?? self, "config")
        }
        scrollView.addSubview(shareItem)
        
        scrollView.contentSize = CGSize(width: 0, height: offY)
        
        updateUI()
    }
    
    func updateUI(){
        
        nameItem.contentField?.text = rule.name
        numbItem.subContentLabel?.text = "\(rule.numberOfRule)"
        let isBlack = rule.defaultStrategy == .DIRECT
        modeItem.contentSwitch?.isOn = isBlack
        modeItem.contentLabel?.text = isBlack ? modeItem.content : modeItem.subContent ?? modeItem.content
        ignoreItem.contentSwitch?.isOn = rule.defaultBlacklistEnable
        noteItem.contentField?.text = rule.note
    }
    
    @objc func currentRuleDidChange(noti:Notification){
        updateUI()
    }
}

enum RuleItemType {
    case Switch
    case Field
    case Label
}

class RuleItemView: UIView {
    
    var textValueChangeHandle:((String) -> Void)?
    var boolValueChangeHandle:((Bool) -> Void)?
    var contentDidClickHandle:(() -> Void)?
    
    var itemHeight:CGFloat = 0
    var titleLabel:UILabel?
    var contentView:UIView
    var contentLabel:UILabel?
    var subContentLabel:UILabel?
    var contentField:UITextField?
    var contentSwitch:UISwitch?
    var describeView:UIView
    var describeLabel:UILabel?
    
    var title:String?
    var content:String
    var subContent:String?
    var isOpen:Bool
    var describe:String?
    var type:RuleItemType
    var showArrow:Bool
    var placeholder:String
    
    init(){
        contentView = UIView()
        describeView = UIView()
        content = ""
        isOpen = false
        type = .Label
        showArrow = false
        placeholder = ""
        super.init(frame: CGRect.zero)
    }
    
    init(title:String?,_ content:String = "", _ subContent:String? ,_ isOpen:Bool = false,describe:String?,type:RuleItemType = .Label,_ showArrow:Bool = false,_ placeholder:String = "") {
        self.title = title
        self.content = content
        self.subContent = subContent
        self.isOpen = isOpen
        self.describe = describe
        self.type = type
        self.showArrow = showArrow
        self.placeholder = placeholder
        contentView = UIView()
        describeView = UIView()
        super.init(frame: CGRect.zero)
        setupUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupUI(){
        var offY:CGFloat = LRSpacing
        let titleHeight:CGFloat = 30
        let contentHeight:CGFloat = 50
        let subContentWidth:CGFloat = 50
        let switchWidth:CGFloat = 50
        let switchHeight:CGFloat = 30
        if let t = title {
            let titleFrame = CGRect(x: LRSpacing, y: offY, width: SCREENWIDTH - LRSpacing * 2, height: titleHeight)
            titleLabel = UILabel.initWith(color: ColorB, font: Font16, text: t, frame: titleFrame)
            addSubview(titleLabel!)
            offY = titleLabel!.frame.maxY
        }
        contentView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: contentHeight)
        contentView.backgroundColor = .white
        contentView.isUserInteractionEnabled = true
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(contentViewDidClick)))
        addSubview(contentView)
        offY = contentView.frame.maxY
        switch type {
        case .Label:
            let arrowW:CGFloat = 20
            let arrowH:CGFloat = 20
            var labelFrame = CGRect(x: LRSpacing, y: 0, width: SCREENWIDTH - LRSpacing * 2 - (showArrow ? arrowW : 0), height: contentHeight)
            if showArrow {
                let arrowIcon = UIImageView(image: UIImage(named: "arrowright"))
                let arrowFrame = CGRect(x: labelFrame.maxX, y: (contentHeight - arrowH)/2, width: arrowW, height: arrowH)
                arrowIcon.frame = arrowFrame
                contentView.addSubview(arrowIcon)
            }
            if let subC = subContent {
                labelFrame = CGRect(x: LRSpacing, y: 0, width: SCREENWIDTH - LRSpacing * 2 - subContentWidth - (showArrow ? arrowW + 5 : 0), height: contentHeight)
                let subLabelFrame = CGRect(x: labelFrame.maxX, y: 0, width: subContentWidth, height: contentHeight)
                subContentLabel = UILabel.initWith(color: ColorC, font: Font16, text: subC, frame: subLabelFrame)
                subContentLabel?.textAlignment = .right
                contentView.addSubview(subContentLabel!)
                if showArrow {
                    
                }
            }
            contentLabel = UILabel.initWith(color: ColorB, font: Font16, text: content, frame: labelFrame)
            contentView.addSubview(contentLabel!)
            break
        case .Field:
            let fieldFrame = CGRect(x: LRSpacing, y: 0, width: SCREENWIDTH - LRSpacing * 2, height: contentHeight)
            contentField = UITextField(frame: fieldFrame)
            contentField?.text = content
            contentField?.font = Font16
            contentField?.textColor = ColorC
            contentField?.placeholder = placeholder
            contentField?.tag = 0
            contentField?.delegate = self
            contentView.addSubview(contentField!)
            contentField?.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
            break
        case .Switch:
            let labelFrame = CGRect(x: LRSpacing, y: 0, width: SCREENWIDTH - LRSpacing * 2 - 50, height: contentHeight)
            contentLabel = UILabel.initWith(color: ColorB, font: Font16, text: content, frame: labelFrame)
            if !isOpen, subContent != nil {
                contentLabel?.text = subContent
            }
            contentView.addSubview(contentLabel!)
            let switchFrame = CGRect(x: SCREENWIDTH - LRSpacing - switchWidth, y: (contentHeight - switchHeight) / 2, width: switchWidth, height: switchHeight)
            contentSwitch = UISwitch(frame: switchFrame)
            contentSwitch?.isOn = isOpen
            contentSwitch?.addTarget(self, action: #selector(switchValueChanged(sender:)), for: .valueChanged)
            contentView.addSubview(contentSwitch!)
            break
        }
        if let s = describe {
            let textHeight = s.textHeight(font: Font14, fixedWidth: SCREENWIDTH - LRSpacing * 2)
            let describeFrame = CGRect(x: LRSpacing, y: 0, width: SCREENWIDTH - LRSpacing * 2, height: textHeight)
            describeLabel = UILabel.initWith(color: ColorC, font: Font14, text: s, frame: describeFrame)
            describeLabel?.numberOfLines = 0
            describeView.addSubview(describeLabel!)
            describeView.frame = CGRect(x: 0, y: offY + 2, width: SCREENWIDTH, height: textHeight)
            offY = describeView.frame.maxY
            addSubview(describeView)
        }
        itemHeight = offY
    }
    
    @objc func switchValueChanged(sender:UISwitch){
        if subContent != nil , !sender.isOn{
            contentLabel?.text = subContent
        }else{
            contentLabel?.text = content
        }
        boolValueChangeHandle?(sender.isOn)
    }
    
    @objc func contentViewDidClick(){
        contentDidClickHandle?()
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
        textValueChangeHandle?(textField.text ?? "")
        
    }
}

extension RuleItemView: UITextFieldDelegate {
 
}
