//
//  BlackRuleListViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/17.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class BlackRuleListViewController: BaseViewController,PopupContentViewController {
    
    var closeHandler: (() -> Void)?
    var items = [RuleItem]()
    
    // tableView
    lazy var tableView: UITableView = {
        let tableViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let tableView = UITableView(frame: tableViewFrame, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(RuleItemCell.self, forCellReuseIdentifier: "RuleItemCell")
        tableView.separatorStyle = .none
        tableView.rowHeight = 50
        return tableView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navTitle = "The rule list is ignored by default".localized
        showLeftBtn = false
        setupUI()
    }
    
    func setupUI(){
        rightBtn.setTitle("Close".localized, for: .normal)
        rightBtn.setTitleColor(ColorM, for: .normal)
        view.addSubview(tableView)
    }
    
    override func rightBtnClick() {
        closeHandler?()
    }
    
    func sizeForPopup(_ popupController: PopupController, size: CGSize, showingKeyboard: Bool) -> CGSize {
        return CGSize(width: SCREENWIDTH, height: SCREENHEIGHT)
    }
    
}

extension BlackRuleListViewController:UITableViewDelegate,UITableViewDataSource {
    
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
        
    }
    
}
