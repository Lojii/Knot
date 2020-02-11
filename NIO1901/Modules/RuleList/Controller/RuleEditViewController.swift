//
//  RuleEditViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class RuleEditViewController: UIViewController {
    
    var rule:Rule
    
    var items = [RuleItem]()
    let operationViewHeight:CGFloat = 50
    let btnW:CGFloat = 50 * 1.5
    let viewHeight = SCREENHEIGHT - NAVGATIONBARHEIGHT

    lazy var tableView: UITableView = {
        let tableViewFrame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: viewHeight - XBOTTOMHEIGHT - operationViewHeight)
        let tableView = UITableView(frame: tableViewFrame, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(RuleItemCell.self, forCellReuseIdentifier: "RuleItemCell")
        tableView.separatorStyle = .none
        tableView.rowHeight = 50
        return tableView
    }()
    
    var cancelBtn:UIButton = UIButton()
    
    lazy var operationView:UIView = {
        let operationFrame = CGRect(x: 0, y: viewHeight - XBOTTOMHEIGHT - operationViewHeight, width: SCREENWIDTH, height: operationViewHeight)
        let operationView = UIView(frame: operationFrame)
        operationView.backgroundColor = ColorF
        let addBtn = UIButton(type: UIButton.ButtonType.system)
        addBtn.frame = CGRect(x: SCREENWIDTH - btnW, y: 0, width: btnW, height: operationViewHeight)
        addBtn.setTitle("Add".localized, for: .normal)
        addBtn.titleLabel?.font = Font16
        addBtn.addTarget(self, action: #selector(addBtnDidClick), for: .touchUpInside)
        operationView.addSubview(addBtn)

        let editBtn = UIButton(type: UIButton.ButtonType.system)
        editBtn.frame = CGRect(x: SCREENWIDTH - btnW * 2, y: 0, width: btnW, height: operationViewHeight)
        editBtn.setTitle("Edit".localized, for: .normal)
        editBtn.titleLabel?.font = Font16
        editBtn.addTarget(self, action: #selector(editBtnDidClick), for: .touchUpInside)
        operationView.addSubview(editBtn)
        
        cancelBtn = UIButton(type: UIButton.ButtonType.system)
        cancelBtn.frame = CGRect(x: SCREENWIDTH, y: 0, width: btnW * 2, height: operationViewHeight)
        cancelBtn.setTitle("Done".localized, for: .normal)
        cancelBtn.titleLabel?.font = Font16
        cancelBtn.addTarget(self, action: #selector(doneBtnDidClick), for: .touchUpInside)
        cancelBtn.backgroundColor = ColorF
        operationView.addSubview(cancelBtn)
        
        return operationView
    }()
    
    init(rule:Rule) {
        self.rule = rule
        self.items = rule.validRuleItems
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(tableView)
        view.addSubview(operationView)
        NotificationCenter.default.addObserver(self, selector: #selector(currentRuleDidChange(noti:)), name: CurrentRuleDidChange, object: nil)
    }
    
    @objc func addBtnDidClick(){
        RuleAddViewController.show(item: nil, rule: rule , viewController: self.parent?.parent ?? self)
    }
    
    @objc func editBtnDidClick(){
        tableView.isEditing = true
        UIView.animate(withDuration: 0.25) {
            self.cancelBtn.frame = CGRect(x: SCREENWIDTH - self.btnW * 2, y: 0, width: self.btnW * 2, height: self.operationViewHeight)
        }
        
    }

    @objc func doneBtnDidClick(){
        tableView.isEditing = false
        UIView.animate(withDuration: 0.25) {
            self.cancelBtn.frame = CGRect(x: SCREENWIDTH, y: 0, width: self.btnW * 2, height: self.operationViewHeight)
        }
    }
    
    @objc func currentRuleDidChange(noti:Notification){
        items = rule.validRuleItems
        tableView.reloadData()
    }
}


extension RuleEditViewController:UITableViewDelegate,UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RuleItemCell") as! RuleItemCell
        let item = items[indexPath.row]
        cell.ruleLineLable.text = "\(item.matchRule.rawValue) \(item.value)"
        var secondLine = "\(item.strategy.rawValue)"
        if item.annotation != nil , item.annotation != "" {
            secondLine.append("(\(item.annotation ?? ""))")
        }
        cell.strategyLable.text = secondLine
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        RuleAddViewController.show(item: item, rule: rule, viewController: self.parent?.parent ?? self)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .delete
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let sLine = items[sourceIndexPath.row]
        let dLine = items[destinationIndexPath.row]
        rule.move(from: sLine.index, to: dLine.index)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let line = items[indexPath.row]
            rule.delete(line.lineType, line.index)
        }
    }
}


class RuleItemCell: UITableViewCell {
    
    var ruleLineLable:UILabel
    var strategyLable:UILabel
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.ruleLineLable = UILabel.initWith(color: ColorB, font: Font14, text: "", frame: CGRect.zero)
        self.strategyLable = UILabel.initWith(color: ColorB, font: Font12, text: "", frame: CGRect.zero)
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupUI(){
        contentView.addSubview(ruleLineLable)
        contentView.addSubview(strategyLable)
        ruleLineLable.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing)
            m.top.equalToSuperview().offset(10)
            m.right.equalToSuperview().offset(-LRSpacing)
        }
        strategyLable.snp.makeConstraints { (m) in
            m.top.equalTo(ruleLineLable.snp.bottom).offset(2)
            m.left.right.equalTo(ruleLineLable)
//            m.height.equalTo(20)
        }
        let line = UIView()
        line.backgroundColor = ColorF
        contentView.addSubview(line)
        line.snp.makeConstraints { (m) in
            m.left.bottom.right.equalToSuperview()
            m.height.equalTo(1)
        }
    }
}

