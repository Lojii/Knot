//
//  RuleListViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/7.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

let CurrentRuleListChange: NSNotification.Name = NSNotification.Name(rawValue: "CurrentRuleListChange")
let CurrentSelectedRuleChanged: NSNotification.Name = NSNotification.Name(rawValue: "CurrentSelectedRuleChanged")

class RuleListViewController: BaseViewController,PopupContentViewController {

    var closeHandler: (() -> Void)?
    var itemSelectedHandler: ((Int) -> Void)?
    
    var currentId:String = ""
    var rules = [Rule]()
    
    // tableView
    lazy var tableView: UITableView = {
        let tableViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let tableView = UITableView(frame: tableViewFrame, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(RuleCell.self, forCellReuseIdentifier: "RuleCell")
        tableView.separatorStyle = .none
        tableView.rowHeight = 60
        return tableView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navTitle = "Rules list".localized
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(loadData), name: CurrentRuleListChange, object: nil)
    }
    
    func setupUI(){
        rightBtn.setTitle("New".localized, for: .normal)
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
        view.addSubview(tableView)
        loadData()
    }
    
    @objc func loadData(){
        currentId = UserDefaults.standard.string(forKey: CurrentRuleId) ?? ""
        rules = Rule.findAll()
        rules.sort { (r1, r2) -> Bool in
            return true//r1.name.localizedCompare(r2.name) == .orderedAscending
        }
//        let defaultRule = Rule()
//        defaultRule.name = "Default"
//        defaultRule.defaultBlacklistEnable = true
//        defaultRule.defaultStrategy = .COPY
//        rules.insert(defaultRule, at: 0)
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    override func rightBtnClick() {
        PopViewController.show(titles: ["Create an empty configuration".localized,"Download the configuration from the URL".localized], viewController: self.parent ?? self) { (index) in
            if index == 0 {
                let vc = RuleDetailViewController(rule: nil)
                if let homeVC = self.parent?.parent {
                    homeVC.present(vc, animated: true, completion: nil)
                }
            }
            if index == 1 {
                IDDialog.id_showInput(msg: "Enter the download URL".localized, leftActionTitle: "Cancel".localized, rightActionTitle: "Download".localized, leftHandler: nil, rightHandler: { (urlStr) in
                    self.downloadConfig(urlStr: urlStr)
                })
            }
        }
    }
    
    func downloadConfig(urlStr:String) {
        guard let url = URL(string: urlStr) else {
            ZKProgressHUD.showError("Please enter the correct URL".localized)
            return
        }
//        ZKProgressHUD.showProgress(0)
        ZKProgressHUD.show()
        DownloadTools.down(url: url, progress: { (per) in
                        print(per)
            if per < 0 {
                return
            }else{
//                ZKProgressHUD.showProgress(per)
                print("进度:\(per)")
            }
        }, complete: { (data, fileUrl) in
            guard let d = data else {
                ZKProgressHUD.dismiss()
                ZKProgressHUD.showError("null file")
                return
            }
            if let conf = String(data: d, encoding: .utf8) {
                let downRule = Rule.fromConfig(conf)
                if downRule.numberOfRule <= 0 {
                    ZKProgressHUD.dismiss()
                    ZKProgressHUD.showError("no rules in conf")
                    return
                }
                if downRule.name == "" {
                    downRule.name = url.lastPathComponent
                }
                try? downRule.saveToDB()
                self.loadData()
                ZKProgressHUD.dismiss()
            }else{
                ZKProgressHUD.dismiss()
                ZKProgressHUD.showError("not a conf")
            }
        }) { (errorStr) in
            ZKProgressHUD.dismiss()
            ZKProgressHUD.showError("\(errorStr)")
            print("Error:\(errorStr)")
        }
    }
    
    @objc func cancelBtnclick() {
        closeHandler?()
    }
    
    func sizeForPopup(_ popupController: PopupController, size: CGSize, showingKeyboard: Bool) -> CGSize {
        return CGSize(width: SCREENWIDTH, height: SCREENHEIGHT)
    }

}

extension RuleListViewController:UITableViewDelegate,UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rules.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "RuleCell") as! RuleCell
        let rule = rules[indexPath.row]
        cell.rule = rule
        cell.detailHandler = { r in
            let options = cell.isSelected ? ["Details".localized,"Create a copy".localized,"Share".localized] : ["Details".localized,"Create a copy".localized,"Share".localized,"Delete".localized]
            PopViewController.show(titles: options, viewController: self.parent ?? self, itemClickHandler: { (index) in
                r?.configParse()
                if index == 0 {
                    let vc = RuleDetailViewController(rule: r ?? Rule())
                    if let homeVC = self.parent?.parent {
                        homeVC.present(vc, animated: true, completion: nil)
                    }
                }
                if index == 1 {
                    let ruleCopy = Rule()
                    ruleCopy.config = r?.config ?? ""
                    ruleCopy.name = "\(r?.name ?? "")\("(copy)".localized)"
                    ruleCopy.createTime = Date().fullSting
                    try? ruleCopy.saveToDB()
                    self.loadData()
                }
                if index == 2 {
                    VisualActivityViewController.share(text: r?.config ?? "", on: self.parent ?? self, "config")
                }
                if index == 3 {
                    try? r?.delete()
                    self.loadData()
                }
            })
        }
        if "\(rule.id?.intValue ?? -1)" == currentId {
            tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let rule = rules[indexPath.row]
        if rule.id == nil {
            UserDefaults.standard.set("", forKey: CurrentRuleId)
        }else{
            UserDefaults.standard.set("\(rule.id!.intValue)", forKey: CurrentRuleId)
        }
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: CurrentSelectedRuleChanged, object: rule)
        closeHandler?()
    }
    
}
