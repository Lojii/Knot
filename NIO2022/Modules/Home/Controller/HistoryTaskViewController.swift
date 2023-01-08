//
//  HistoryTaskViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/25.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NetworkExtension
import NIOMan

class HistoryTaskViewController: BaseViewController {

//    var vpnStatus: NEVPNStatus = .disconnected
    
    var tasks = [Task]()
    var taskIDS = [Int]()
    var _listEditing: Bool = false
    var listEditing: Bool {
        get { return _listEditing }
        set {
            _listEditing = newValue
            tableView.setEditing(_listEditing, animated: true)
            rightBtn.setTitle(_listEditing ? "Cancel".localized : "Edit".localized, for: .normal)
    
            let tableFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
            let tableFrameEdit = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT - 44 - XBOTTOMHEIGHT)
            let editToolFrame = CGRect(x: 0, y: tableFrame.maxY, width: SCREENWIDTH, height: 44 + XBOTTOMHEIGHT)
            let editToolFrameEdit = CGRect(x: 0, y: tableFrameEdit.maxY, width: SCREENWIDTH, height: 44 + XBOTTOMHEIGHT)
            UIView.animate(withDuration: 0.3, animations: {
                self.tableView.frame = self.listEditing ? tableFrameEdit : tableFrame
                self.editToolView.frame = self.listEditing ? editToolFrameEdit : editToolFrame
            }) { (finished) in
                if finished {
                    self.editToolView.isHidden = !self.listEditing
                }
            }
        }
    }
    var _selectedIndexs = [Int]()
    var selectedIndexs: [Int] {
        get { return _selectedIndexs }
        set {
            _selectedIndexs = newValue
            if _selectedIndexs.count > 0 {
                nextBtn.setTitle("\("Next".localized)(\(_selectedIndexs.count)/\(taskIDS.count))", for: .normal)
            }else{
                nextBtn.setTitle("Next".localized, for: .normal)
            }
        }
    }
    var selectAll = false
    var outputType:OutputType = .URL
    var nextBtn = UIButton()
    lazy var editToolView: UIView = {
        let H:CGFloat = 44
        let editToolFrame = CGRect(x: 0, y: self.tableView.frame.maxY, width: SCREENWIDTH, height: H + XBOTTOMHEIGHT)
        let editToolView = UIView(frame: editToolFrame)
        editToolView.backgroundColor = ColorF
        let selectAllBtn = UIButton()
        selectAllBtn.frame = CGRect(x: 0, y: 0, width: 70, height: H)
        selectAllBtn.setTitle("Check all".localized, for: .normal)
        selectAllBtn.setTitleColor(ColorM, for: .normal)
        selectAllBtn.titleLabel?.font = Font16
        selectAllBtn.addTarget(self, action: #selector(selectAllBtnDidClick), for: .touchUpInside)
        let invertBtn = UIButton()
        invertBtn.frame = CGRect(x: selectAllBtn.frame.maxX, y: 0, width: 70, height: H)
        invertBtn.setTitle("Invert Check".localized, for: .normal)
        invertBtn.setTitleColor(ColorM, for: .normal)
        invertBtn.titleLabel?.font = Font16
        invertBtn.addTarget(self, action: #selector(invertAllBtnDidClick), for: .touchUpInside)
        nextBtn = UIButton()
        nextBtn.setTitle("Next".localized, for: .normal)
        nextBtn.frame = CGRect(x: SCREENWIDTH - 150, y: 0, width: 150, height: H)
        nextBtn.setTitleColor(ColorM, for: .normal)
        nextBtn.titleLabel?.font = Font16
        nextBtn.addTarget(self, action: #selector(nextBtnDidClick), for: .touchUpInside)
        editToolView.addSubview(selectAllBtn)
        editToolView.addSubview(invertBtn)
        editToolView.addSubview(nextBtn)
        return editToolView
    }()
    
    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT), style: .plain)
        tableView.register(UINib(nibName: "TaskCell", bundle: nil), forCellReuseIdentifier: "TaskCell")
        tableView.rowHeight = 80
        tableView.separatorStyle = .none
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.configRefreshHeader(container: self) {
            self.loadData()
        }
        tableView.switchRefreshHeader(to: .refreshing)
        return tableView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        NotificationCenter.default.addObserver(self, selector: #selector(vpnDidChange(noti:)), name: NSNotification.Name.NEVPNStatusDidChange, object: nil)
        navTitle = "Historical task".localized
        rightBtn.setTitle("Edit".localized, for: .normal)
        rightBtn.setTitleColor(ColorA, for: .normal)
        // tableView
        view.addSubview(tableView)
        // editTool
        view.addSubview(editToolView)
    }
    
    func loadData(){
        NEManager.shared.loadCurrentStatus { status in
            var currentTaskId:String?
            if(status == .on){
                // 排除当前任务
                let gud = UserDefaults(suiteName: GROUPNAME)
                if let taskId = gud?.value(forKey: CURRENTTASKID) as? String {
                    currentTaskId = taskId
                }
            }
            // 排除currentTaskId
            DispatchQueue.global().async {
                self.tasks = Task.find(excludeTaskId: currentTaskId)
                self.taskIDS = Task.getAllIds(excludeTaskId: currentTaskId)
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                    self.tableView.switchRefreshHeader(to: .normal(.none, 0))
                }
            }
        }
        
    }
    
    override func rightBtnClick() {
        if listEditing {
            listEditing = false
            selectedIndexs.removeAll()
            return
        }
        PopViewController.show(titles: ["Export link".localized,"Export cURL".localized,"Export HTTP Archive (.har)".localized,"Delete".localized], viewController: self) { (index) in
            self.listEditing = true
            if index == 0 {
                self.outputType = .URL
                self.navBar.titleLable.text = "Export link".localized
            }
            if index == 1 {
                self.outputType = .CURL
                self.navBar.titleLable.text = "Export cURL".localized
            }
            if index == 2 {
                self.outputType = .HAR
                self.navBar.titleLable.text = "Export HTTP Archive (.har)".localized
            }
            if index == 3 {
                self.outputType = .DEL
                self.navBar.titleLable.text = "Delete".localized
            }
        }
    }
    
//    @objc func vpnDidChange(noti:Notification) -> Void {
//        guard let tunnelPS = noti.object as? NETunnelProviderSession else {
//            print("Not NETunnelProviderSession !")
//            return
//        }
//        if vpnStatus != tunnelPS.status {
//            vpnStatus = tunnelPS.status
//            //
//            self.tableView.switchRefreshHeader(to: .refreshing)
//        }
//    }
    
    @objc func selectAllBtnDidClick(){
        selectedIndexs.removeAll()
        for taskId in taskIDS {
            selectedIndexs.append(taskId)
        }
        tableView.reloadData()
    }
    
    @objc func invertAllBtnDidClick(){
        var tmpIds = [Int]()
        for taskId in taskIDS {
            tmpIds.append(taskId)
        }
        tmpIds.removeAll { (id) -> Bool in
            return selectedIndexs.contains(id)
        }
        selectedIndexs = tmpIds
        tableView.reloadData()
    }
    
    @objc func nextBtnDidClick(){
        print("\(selectedIndexs)")
        let actionBlock = {
            ZKProgressHUD.show()
            OutputUtil.taskDoBatch(ids: self.selectedIndexs, type: self.outputType) { (filePath) in
                ZKProgressHUD.dismiss()
                
                if filePath == "" {
                    if self.outputType == .DEL {
                        ZKProgressHUD.showSuccess("Success".localized)
                        self.listEditing = false
                        self.selectedIndexs.removeAll()
                        self.tableView.switchRefreshHeader(to: .refreshing)
                        NotificationCenter.default.post(name: HistoryTaskDidChanged, object: nil)
                    }
                    return
                }
                guard let fp = filePath else {
                    ZKProgressHUD.showError("Export failed".localized)
                    return
                }
                if let fileUrl = URL(string: fp) {
                    let vc = VisualActivityViewController(url: fileUrl)
                    //(UIActivity.ActivityType?, Bool, [Any]?, Error?) -> Void
                    vc.completionWithItemsHandler = { (type,success,items,error) in
                        try? FileManager.default.removeItem(at: fileUrl)
                    }
                    self.present(vc, animated: true, completion: nil)
                }
            }
        }
        if outputType == .DEL {
            actionBlock()
        }else{
            KnotPurchase.check(.HappyKnot) { res in
                if(res){
                    actionBlock()
                }else{
                    ZKProgressHUD.showError("Purchase failed".localized)
                }
            }
        }
    }

}

extension HistoryTaskViewController:UITableViewDelegate, UITableViewDataSource,TaskCellDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tasks.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell") as! TaskCell
//        cell.selectionStyle = .none
        let task = tasks[indexPath.row]
        cell.task = task
        cell.delegate = self
        cell.indexPath = indexPath
        if tableView.isEditing {
            let selected = selectedIndexs.contains(task.id?.intValue ?? -1)
            if selected {
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            }
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing { return }
        navigationController?.pushViewController(SessionListViewController(task: tasks[indexPath.row]), animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .none
    }
    
    func taskCellDidSelected(task: Task?, selected: Bool, indexPath: IndexPath?) {
        guard let id = task?.id, let index = indexPath else { return }
        if !selected {
            selectedIndexs.append(id.intValue)
            tableView.selectRow(at: index, animated: false, scrollPosition: .none)
        }else{
            if selectedIndexs.contains(id.intValue) {
                selectedIndexs.removeAll { (sid) -> Bool in
                    return sid == id.intValue
                }
            }
            tableView.deselectRow(at: index, animated: false)
        }
    }
}
