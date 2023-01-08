//
//  MatchHostListVC.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/7.
//

import UIKit
import NIOMan
import SnapKit

class MatchHostListVC: BaseViewController {
    
    var rule:Rule!
    var isBlack:Bool = false
    
    var tableView:UITableView!
    
    init(rule:Rule, isBlack:Bool = false) {
        self.rule = rule
        self.isBlack = isBlack
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUI()
    }
    
    func setUI(){
        navTitle = "匹配列表"
        
        if !isBlack {
            rightBtn.setTitle("Add", for: .normal)
            rightBtn.setTitleColor(ColorM, for: .normal)
        }
        
        let tv = UITableView(frame: CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT), style: .grouped)
        tv.delegate = self
        tv.dataSource = self
        tableView = tv
        view.addSubview(tableView)
    }
    
    override func rightBtnClick() {
        let addVC = MatchHostEditVC()
        addVC.doneBlock = { (value, index) in
            self.lineChange(value, index)
        }
        present(addVC, animated: true)
    }
    
    func lineChange(_ value: String?,_ index: Int?){
        var hosts = rule.match_host_array
        if index == -1 && value != "" { // add
            if hosts.contains(value!) {
                return
            }else{
                hosts.append(value!)
            }
        }
        if index != -1 {
            if value == "" { // del
                hosts.remove(at: index!)
            }else{ // edit
                if hosts[index!] == value! { return }
                if hosts.contains(value!) {
                    hosts.remove(at: index!)
                }else{
                    hosts.remove(at: index!)
                    hosts.insert(value!, at: index!)
                }
            }
        }
        rule.match_host_array = hosts
        tableView.reloadData()
        // 通知更新
        NotificationCenter.default.post(name: CurrentRuleDidChange, object: nil)
    }
    
    deinit {
        print("MatchHostListVC deinit !")
    }
}

extension MatchHostListVC: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isBlack {
            if rule.ignoreSuggest() {
                return rule.ignore_host_array.count
            }else{
                return 0
            }
        }else{
            return rule.match_host_array.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var host = ""
        if isBlack {
            host = rule.ignore_host_array[indexPath.row]
        }else{
            host = rule.match_host_array[indexPath.row]
        }
        var cell = tableView.dequeueReusableCell(withIdentifier: "cell")
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: "cell")
        }
        cell?.textLabel?.font = Font16
        cell?.textLabel?.text = host
        if !isBlack {
            cell?.accessoryType = .disclosureIndicator
        }
        return cell!
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headV = UIView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 50))
//        headV.backgroundColor = .
        let label = UILabel()
        label.text = "Suggest ruled out".localized
        label.textColor = ColorB
        label.font = Font16
        headV.addSubview(label)
        label.snp.makeConstraints { make in
            make.centerY.equalTo(headV.snp.centerY)
            make.left.equalTo(headV.snp_left).offset(LRSpacing)
        }
        let switchBtn = UISwitch()
        switchBtn.isOn = rule.ignoreSuggest()
        switchBtn.addTarget(self, action: #selector(switchValueChanged(sender:)), for: .valueChanged)
        headV.addSubview(switchBtn)
        switchBtn.snp.makeConstraints { make in
            make.centerY.equalTo(headV.snp.centerY)
            make.right.equalTo(headV.snp_right).offset(-LRSpacing)
            
        }
        return headV
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if isBlack {
            return 50
        }else{
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return !isBlack
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let action = UITableViewRowAction(style: .destructive, title: "Delete".localized) { a, i in
            self.lineChange("", i.row)
        }
        return [action]
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isBlack {
            return
        }else{
            let host = rule.match_host_array[indexPath.row]
            let addVC = MatchHostEditVC()
            addVC.index = indexPath.row
            addVC.value = host
            addVC.doneBlock = { (value, index) in
                self.lineChange(value, index)
            }
            present(addVC, animated: true)
        }
    }
    
    @objc func switchValueChanged(sender:UISwitch){
        rule.setIgnoreSuggest(sender.isOn)
        tableView.reloadData()
        NotificationCenter.default.post(name: CurrentRuleDidChange, object: nil)
    }
    
}
