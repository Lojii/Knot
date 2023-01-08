//
//  ConfigViewController.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/7.
//

import UIKit
import NIOMan

public let CurrentRuleDidChange: NSNotification.Name = NSNotification.Name(rawValue: "CurrentRuleDidChange")

class ConfigViewController: BaseViewController {

    var rule:Rule
    var isNew = false
    var ruleChanged = false
    
    var nameItem = RuleItemView()
    var numbItem = RuleItemView()
    var modeItem = RuleItemView()
    var ignoreItem = RuleItemView()
    var textEditItem = RuleItemView()
    var noteItem = RuleItemView()
//    var shareItem = RuleItemView()
    
    var interactivePopGestureRecognizer: UIGestureRecognizer?

    lazy var scrollView: UIScrollView = {
        let scrollViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let scrollView = UIScrollView(frame: scrollViewFrame)
        scrollView.backgroundColor = ColorF
        return scrollView
    }()
    
    init(ruleID:NSNumber?) {
        if ruleID == nil {
            let newRule = Rule()
            newRule.name = "New config"
            newRule.setIgnoreSuggest(true)
            newRule.modelType = .Black
            newRule.author = "Knot"
            newRule.match_host_array = []
            newRule.create_time = Date().fullSting
            ruleChanged = true
            self.rule = newRule
        }else{
            self.rule = Rule.find(id: ruleID!)!
        }
        
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        print("---------- ConfigViewController deinit !")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer = navigationController?.interactivePopGestureRecognizer
        NotificationCenter.default.addObserver(self, selector: #selector(currentRuleDidChange(noti:)), name: CurrentRuleDidChange, object: nil)
        setupUI()
    }

    func setupUI(){
        navTitle = self.rule.name
        rightBtn.setTitle("Save".localized, for: .normal)
        rightBtn.setTitleColor(ColorM, for: .normal)
        
        view.addSubview(scrollView)
        // 名称
        var offY:CGFloat = 0
        nameItem = RuleItemView(title: "Name".localized, content: rule.name, subContent: nil, isOpen: false, describe: nil, type: .Field, showArrow: false, placeholder: "Enter a name".localized)
        nameItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: nameItem.itemHeight)
        offY = nameItem.frame.maxY
        nameItem.textValueChangeHandle = {[weak self] name in
            self?.ruleChanged = true
            self?.rule.name = name
        }
        scrollView.addSubview(nameItem)
        // 备注
        noteItem = RuleItemView(title: "Remark".localized, content: rule.note, subContent: nil, isOpen: false, describe: nil, type: .Field, showArrow: false,  placeholder: "Enter remarks".localized)
        noteItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: noteItem.itemHeight)
        offY = noteItem.frame.maxY
        noteItem.textValueChangeHandle = { [weak self] note in
            self?.ruleChanged = true
            self?.rule.note = note
        }
        scrollView.addSubview(noteItem)
        // 匹配列表
        numbItem = RuleItemView(title: "Matching Host".localized, content: rule.match_host == "" ? "Click on add".localized : rule.match_host, subContent: nil, isOpen: false, describe: "The wildcard * is supported, for example, *.apple.com".localized, type: .Label, showArrow: true)
        numbItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: numbItem.itemHeight)
        offY = numbItem.frame.maxY
        numbItem.contentDidClickHandle = {[weak self] in
            if let welf = self {
                let vc = MatchHostListVC(rule: welf.rule)
                welf.navigationController?.pushViewController(vc, animated: true)
            }
        }
        scrollView.addSubview(numbItem)
        // 模式
        modeItem = RuleItemView(title: nil, content: "Currently in blacklist mode".localized, subContent: "Currently in whitelist mode".localized, isOpen: rule.modelType == .Black, describe: "Blacklist mode describe".localized, type: .Switch)
        modeItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: modeItem.itemHeight)
        offY = modeItem.frame.maxY
        modeItem.boolValueChangeHandle = { [weak self] isOpen in
            self?.ruleChanged = true
            self?.rule.modelType = isOpen ? .Black : .White
        }
        scrollView.addSubview(modeItem)
        // 建议忽略项
        ignoreItem = RuleItemView(title: "Suggest to ignore".localized, content: rule.ignoreSuggest() ? rule.ignore_host_array.joined(separator: ",") : "Click on add".localized, subContent: nil, isOpen: true, describe: "These domains require specific certificates or error analysis requests that are recommended to be ignored, for example apple.com".localized, type: .Label, showArrow: true)
        ignoreItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: ignoreItem.itemHeight)
        offY = ignoreItem.frame.maxY
        ignoreItem.contentDidClickHandle = {[weak self] in
            if let welf = self {
                let vc = MatchHostListVC(rule: welf.rule, isBlack: true)
                welf.navigationController?.pushViewController(vc, animated: true)
            }
        }
        scrollView.addSubview(ignoreItem)
//        // 分享
//        shareItem = RuleItemView(title: nil, content: "Share".localized, subContent: nil, isOpen: true, describe: nil, type: .Label, showArrow: true)
//        shareItem.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: shareItem.itemHeight)
//        offY = shareItem.frame.maxY
//        shareItem.contentDidClickHandle = {[weak self] in
//            if self == nil { return }
//            VisualActivityViewController.share(text: self!.rule.jsonConfig, on: self!, "knot", "\(self!.rule.name)")
//        }
//        scrollView.addSubview(shareItem)
        //
        scrollView.contentSize = CGSize(width: 0, height: offY)
        updateUI()
    }

    func updateUI(){
        nameItem.contentField?.text = rule.name
        numbItem.contentLabel?.text = rule.match_host == "" ? "Click on add".localized : rule.match_host
        modeItem.contentSwitch?.isOn = rule.modelType == .Black
        modeItem.contentLabel?.text = rule.modelType == .Black ? modeItem.content : modeItem.subContent
        ignoreItem.contentLabel?.text = rule.ignoreSuggest() ? rule.ignore_host_array.joined(separator: ",") : "Click on add".localized
        rule.note = noteItem.contentField?.text ?? ""
    }

    @objc func currentRuleDidChange(noti:Notification){
        ruleChanged = true
        updateUI()
    }
    
    func saveRule() -> Bool{
        if rule.name == "" {
            ZKProgressHUD.showError("The name cannot be empty".localized)
            return false
        }
        // 白名单模式且无匹配列表，则提示错误
        if rule.modelType == .White && rule.match_host_array.count <= 0{
            ZKProgressHUD.showError("In whitelist mode, the matching list cannot be empty".localized)
            return false
        }
        try? rule.save()
        // 发送消息给NE
        let gud = UserDefaults(suiteName: GROUPNAME)
        if let currentConfig = gud?.string(forKey: CURRENTRULEID), currentConfig == "\(rule.id!.intValue)" {
            NotificationCenter.default.post(name: CurrentSelectedRuleChangedNoti, object: rule)
            NEManager.shared.sendMessage(msg: ConfigDidChangeAppMessage)
        }
        return true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        interactivePopGestureRecognizer?.isEnabled = true
    }
    
    override func backBtnclick() {
        // 判断是否更改过，提示保存
        cancelBtnclick()
    }
    
    override func rightBtnClick() {
        if saveRule() {
            NotificationCenter.default.post(name: CurrentRuleListChange, object: nil)
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc func cancelBtnclick(){
        if ruleChanged {
            weak var weakSelf = self
            IDDialog.id_show(title: "Save changes or not".localized, msg: nil, countDownNumber: nil, leftActionTitle:"Cancel".localized, rightActionTitle: "Ok".localized, leftHandler: {
//                if let welf = weakSelf {
                    weakSelf?.navigationController?.popViewController(animated: true)
//                }
            }) {
                if let welf = weakSelf {
                    if welf.saveRule() {
                        NotificationCenter.default.post(name: CurrentRuleListChange, object: nil)
                        welf.navigationController?.popViewController(animated: true)
                    }
                }
            }
        }else{
            navigationController?.popViewController(animated: true)
        }
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

    init(title:String?, content:String = "", subContent:String? , isOpen:Bool = false,describe:String?,type:RuleItemType = .Label, showArrow:Bool = false, placeholder:String = "") {
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
