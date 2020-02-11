//
//  RuleAddViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class RuleAddViewController: UIViewController, PopupContentViewController {
    
    var closeHandler:(() -> Void)?
    
    let titleHeight:CGFloat = 30
    
    var item:RuleItem?
    var rowIndex:Int
    var rule:Rule
    // 类型
    var typeHeadView:UIView = UIView()
    var typeViewMaxHeight:CGFloat = 0
    // 内容
    var valueView:UIView = UIView()
    var valueField = UITextField()
    var describeLabel = UILabel()
    var describeLabelHeight:CGFloat = 0
    var valueViewMaxHeight:CGFloat = 0
    // 备注
    var noteView:UIView = UIView()
    var noteField = UITextField()
    var noteViewMaxHeight:CGFloat = 0
    // 操作
    var operationView:UIView = UIView()
    let operationViewHeight:CGFloat = 50
    
    var typeIndex = 0
    let types:[MatchRule] = [.DOMAIN,.DOMAINKEYWORD,.DOMAINSUFFIX,.USERAGENT,.URLREGEX]
    let describes:[String] = ["Enter a matching domain name, for example:www.google.com".localized,
                          "Enter a matching domain name keyword".localized,"Enter a matching domain suffix, for example google.com".localized,
                          "Match request user-agent, support wildcard * and ?".localized,
                          "Enter the regular expression that matches the URL".localized]
    var typeBtns:[UIButton] = [UIButton]()

    init(item:RuleItem?,_ index:Int = 0, rule:Rule) {
        self.item = item
        self.rowIndex = index
        self.rule = rule
        super.init(nibName: nil, bundle: nil)
        if item != nil {
            if item?.matchRule == .DOMAIN { typeIndex = 0 }
            if item?.matchRule == .DOMAINKEYWORD { typeIndex = 1 }
            if item?.matchRule == .DOMAINSUFFIX { typeIndex = 2 }
            if item?.matchRule == .USERAGENT { typeIndex = 3 }
            if item?.matchRule == .URLREGEX { typeIndex = 4 }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        let configuration = WHC_KeyboardManager.share.addMonitorViewController(self.parent?.parent ?? self)
//        configuration.enableHeader = false
        view.backgroundColor = .white
        setupUI()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    func setupUI(){
        addTypeView()
        addValueView()
        addNoteView()
        addOperationView()
        //
        
    }
    
    func addTypeView(){
        view.addSubview(typeHeadView)
        var offY:CGFloat = LRSpacing
        
        let typeTitleFrame = CGRect(x: LRSpacing, y: offY, width: SCREENWIDTH - LRSpacing * 2, height: titleHeight)
        let typeTitleLabel = UILabel.initWith(color: ColorA, font: Font16, text: "Type".localized, frame: typeTitleFrame)
        offY = typeTitleLabel.frame.maxY + 5
        typeHeadView.addSubview(typeTitleLabel)
        typeHeadView.addLine(offY: typeTitleLabel.frame.maxY, lineWidth: SCREENWIDTH)
        var offX:CGFloat = LRSpacing
        let btnHeight:CGFloat = 30
        let maxWidth = SCREENWIDTH - LRSpacing * 2
        let hSpacing:CGFloat = LRSpacing
        let vSpacing:CGFloat = 5
        for index in 0..<types.count {
            let type = types[index]
            var w = type.rawValue.textWidth(font: Font16) + 10
            if w > maxWidth { w = maxWidth }
            if offX + w > maxWidth {
                offX = LRSpacing
                offY = offY + btnHeight + vSpacing
            }
            let frame = CGRect(x: offX, y: offY, width: w, height: btnHeight)
            let typeBtn = UIButton(frame: frame)
            typeBtn.titleLabel?.font = Font16
            typeBtn.setTitle(type.rawValue, for: .normal)
            typeBtn.setTitleColor(ColorB, for: .normal)
            typeBtn.setTitleColor(.white, for: .selected)
            typeBtn.setBackgroundImage(UIImage.renderImageWithColor(ColorF, size: CGSize(width: 1, height: 1)), for: .normal)
            typeBtn.setBackgroundImage(UIImage.renderImageWithColor(ColorSG, size: CGSize(width: 1, height: 1)), for: .selected)
            typeBtn.addTarget(self, action: #selector(typeBtnDidClick(sender:)), for: .touchUpInside)
            typeBtn.layer.cornerRadius = 10
            typeBtn.clipsToBounds = true
            typeBtn.tag = index
            typeHeadView.addSubview(typeBtn)
            typeBtns.append(typeBtn)
            offX = offX + w + hSpacing
            typeBtn.isSelected = index == typeIndex
        }
        offY = offY + btnHeight + vSpacing
        typeHeadView.addLine(offY: offY, lineWidth: SCREENWIDTH)
        typeHeadView.snp.makeConstraints { (m) in
            m.top.left.right.equalToSuperview()
            m.height.equalTo(offY)
        }
        typeViewMaxHeight = offY
    }
    
    func addValueView(){
        var offY = LRSpacing
        view.addSubview(valueView)
        let valueTitleFrame = CGRect(x: LRSpacing, y: offY, width: SCREENWIDTH - LRSpacing * 2, height: titleHeight)
        let valueTitleLabel = UILabel.initWith(color: ColorA, font: Font16, text: "Value".localized, frame: valueTitleFrame)
        valueView.addSubview(valueTitleLabel)
        offY = valueTitleFrame.maxY
        valueView.addLine(offY: offY, lineWidth: SCREENWIDTH)
        valueField = UITextField(frame: CGRect(x: LRSpacing, y: offY, width: SCREENWIDTH - LRSpacing * 2, height: 50))
        valueField.placeholder = "Enter Please".localized
        valueField.font = Font16
        valueField.textColor = ColorB
        valueField.text = item?.value
        valueView.addSubview(valueField)
        offY = valueField.frame.maxY
        valueView.addLine(offY: offY, lineWidth: SCREENWIDTH)
        let describe = describes[typeIndex]
        describeLabelHeight = describe.textHeight(font: Font14, fixedWidth: SCREENWIDTH - LRSpacing * 2)
        let noteLabelFrame = CGRect(x: LRSpacing, y: offY + 3, width: SCREENWIDTH - LRSpacing * 2, height: describeLabelHeight)
        describeLabel = UILabel.initWith(color: ColorC, font: Font14, text: describe, frame: noteLabelFrame)
        describeLabel.numberOfLines = 0
        valueView.addSubview(describeLabel)
        offY = noteLabelFrame.maxY
        valueView.snp.makeConstraints { (m) in
            m.top.equalTo(typeHeadView.snp.bottom)
            m.left.right.equalToSuperview()
            m.height.equalTo(offY)
        }
        
        var maxDesHeight:CGFloat = 0
        for des in describes {
            let desHeight = des.textHeight(font: Font14, fixedWidth: SCREENWIDTH - LRSpacing * 2)
             maxDesHeight = CGFloat.maximum(desHeight, maxDesHeight)
        }
        valueViewMaxHeight = maxDesHeight + valueField.frame.maxY
    }
    
    func addStrategyView(){
        
    }
    
    func addNoteView(){
        var offY = LRSpacing
        view.addSubview(noteView)
        let noteTitleFrame = CGRect(x: LRSpacing, y: offY, width: SCREENWIDTH - LRSpacing * 2, height: titleHeight)
        let noteTitleLabel = UILabel.initWith(color: ColorA, font: Font16, text: "Remark".localized, frame: noteTitleFrame)
        noteView.addSubview(noteTitleLabel)
        offY = noteTitleFrame.maxY
        noteView.addLine(offY: offY, lineWidth: SCREENWIDTH)
        noteField = UITextField(frame: CGRect(x: LRSpacing, y: offY, width: SCREENWIDTH - LRSpacing * 2, height: 50))
        noteField.placeholder = "Enter remarks".localized
        noteField.font = Font16
        noteField.textColor = ColorB
        noteField.text = item?.annotation
        noteView.addSubview(noteField)
        offY = noteField.frame.maxY
        noteView.snp.makeConstraints { (m) in
            m.top.equalTo(valueView.snp.bottom)
            m.left.right.equalToSuperview()
            m.height.equalTo(offY)
        }
        noteViewMaxHeight = offY
    }
    
    func addOperationView(){
        view.addSubview(operationView)
        let cancelBtn = UIButton(type: .system)
        cancelBtn.titleLabel?.font = Font16
        cancelBtn.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH / 3, height: operationViewHeight)
        
        let centerBtn = UIButton(type: .system)
        centerBtn.titleLabel?.font = Font16
        centerBtn.frame = CGRect(x: cancelBtn.frame.maxX, y: 0, width: SCREENWIDTH / 3, height: operationViewHeight)
        
        let doneBtn = UIButton(type: .system)
        doneBtn.titleLabel?.font = Font16
        doneBtn.frame = CGRect(x: centerBtn.frame.maxX, y: 0, width: SCREENWIDTH / 3, height: operationViewHeight)
        
        cancelBtn.setTitle("Cancel".localized, for: .normal)
        cancelBtn.addTarget(self, action: #selector(cancelBtnDidClick), for: .touchUpInside)
        if item != nil { // 取消、删除、完成
            centerBtn.setTitleColor(ColorR, for: .normal)
            centerBtn.setTitle("Delete".localized, for: .normal)
            centerBtn.addTarget(self, action: #selector(deleteBtnDidClick), for: .touchUpInside)
            doneBtn.setTitle("Done".localized, for: .normal)
            doneBtn.addTarget(self, action: #selector(doneBtnDidClick), for: .touchUpInside)
        }else{ // 取消、添加后继续添加、添加
            centerBtn.setTitle("Continue to add".localized, for: .normal)
            centerBtn.addTarget(self, action: #selector(continueBtnDidClick), for: .touchUpInside)
            doneBtn.setTitle("Add".localized, for: .normal)
            doneBtn.addTarget(self, action: #selector(addBtnDidClick), for: .touchUpInside)
        }
        operationView.addSubview(cancelBtn)
        operationView.addSubview(centerBtn)
        operationView.addSubview(doneBtn)
        operationView.snp.makeConstraints { (m) in
            m.left.right.equalToSuperview()
            m.bottom.equalToSuperview().offset(-XBOTTOMHEIGHT)
            m.height.equalTo(operationViewHeight)
        }
        operationView.addLine(offY: 0, lineWidth: SCREENWIDTH)
    }
    
    @objc func cancelBtnDidClick(){
        closeHandler?()
    }
    @objc func deleteBtnDidClick(){
        // 删除
        guard let line = item else {
            return
        }
        if rule.delete(line.lineType, line.index) {
            ZKProgressHUD.showSuccess(autoDismissDelay:0.2)
        }else{
            ZKProgressHUD.showError("Delete failed".localized)
        }
        closeHandler?()
    }
    @objc func doneBtnDidClick(){
        // 修改
        guard let line = item else {
            return
        }
        let value = valueField.text?.trimmingCharacters(in: .whitespaces)
        if value == "" || value == nil {
            ZKProgressHUD.showInfo("The content cannot be empty".localized)
        }else{
            let itemItem = RuleItem()
            itemItem.index = line.index
            itemItem.matchRule = types[typeIndex]
            itemItem.value = value ?? "-"
            itemItem.strategy = .DEFAULT
            let noteValue = noteField.text?.trimmingCharacters(in: .whitespaces)
            if noteValue != nil , noteValue != "" {
                itemItem.annotation = noteValue
            }
            
            if rule.replace(line.lineType, itemItem, itemItem.index) {
                ZKProgressHUD.showSuccess(autoDismissDelay:0.2)
                closeHandler?()
            }else{
                ZKProgressHUD.showError("Change failed".localized)
            }
        }
        
        
    }
    @objc func continueBtnDidClick(){
        let value = valueField.text?.trimmingCharacters(in: .whitespaces)
        if value == "" || value == nil {
            ZKProgressHUD.showInfo("The content cannot be empty".localized)
        }else{
            let itemItem = RuleItem()
            itemItem.matchRule = types[typeIndex]
            itemItem.value = value ?? "-"
            itemItem.strategy = .DEFAULT
            let noteValue = noteField.text?.trimmingCharacters(in: .whitespaces)
            if noteValue != nil , noteValue != "" {
                itemItem.annotation = noteValue
            }
            if rule.add(.Rule, itemItem) {
                ZKProgressHUD.showSuccess(autoDismissDelay:0.2)
            }else{
                ZKProgressHUD.showError("Add failed".localized)
            }
        }
    }
    @objc func addBtnDidClick(){
        // 添加
        let value = valueField.text?.trimmingCharacters(in: .whitespaces)
        if value == "" || value == nil {
            ZKProgressHUD.showInfo("The content cannot be empty".localized)
        }else{
            let itemItem = RuleItem()
            itemItem.matchRule = types[typeIndex]
            itemItem.value = value ?? "-"
            itemItem.strategy = .DEFAULT
            let noteValue = noteField.text?.trimmingCharacters(in: .whitespaces)
            if noteValue != nil , noteValue != "" {
                itemItem.annotation = noteValue
            }
            if rule.add(.Rule, itemItem) {
                ZKProgressHUD.showSuccess(autoDismissDelay:0.2)
                closeHandler?()
            }else{
                ZKProgressHUD.showError("Add failed".localized)
            }
        }
    }
    
    @objc func typeBtnDidClick(sender:UIButton){
        if sender.isSelected { return }
        for btn in typeBtns{ btn.isSelected = false }
        sender.isSelected = true
        typeIndex = sender.tag
        item?.matchRule = types[typeIndex]
        // update ui
        let describe = describes[typeIndex]
        describeLabel.text = describe
        let newDescribeLabelHeight = describe.textHeight(font: Font14, fixedWidth: SCREENWIDTH - LRSpacing * 2)
        describeLabel.frame = CGRect(x: describeLabel.frame.origin.x, y: describeLabel.frame.origin.y, width: describeLabel.frame.width, height: newDescribeLabelHeight)
        let newHeight = valueView.frame.height - (describeLabelHeight - newDescribeLabelHeight)
        describeLabelHeight = newDescribeLabelHeight
        valueView.snp.updateConstraints { (m) in
            m.top.equalTo(typeHeadView.snp.bottom)
            m.left.right.equalToSuperview()
            m.height.equalTo(newHeight)
        }
        
    }

    static func show(item:RuleItem?, rule:Rule, viewController:UIViewController ){
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
        let container = RuleAddViewController(item: item, rule: rule)
        container.closeHandler = { popup.dismiss() }
        popup.show(container)
    }
    
    func sizeForPopup(_ popupController: PopupController, size: CGSize, showingKeyboard: Bool) -> CGSize {
        return CGSize(width: SCREENWIDTH, height: typeViewMaxHeight + valueViewMaxHeight + noteViewMaxHeight + operationViewHeight + XBOTTOMHEIGHT)
    }
}

extension UIView {
    func addLine(color:UIColor = ColorF,offY:CGFloat,offX:CGFloat = 0,lineWidth:CGFloat){
        let line = UIView(frame: CGRect(x: offX, y: offY, width: lineWidth, height: 1))
        line.backgroundColor = color
        addSubview(line)
    }
}
