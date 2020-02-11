//
//  HistoryView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/28.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

protocol HistoryViewDelegate: class {
    func taskDidClick(task:Task)
    func taskModeDidClick()
}

class HistoryView: UIView, UITableViewDelegate, UITableViewDataSource {
    
    weak var delegate:HistoryViewDelegate?
    
    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: CGRect(x: 0, y: 34, width: SCREENWIDTH, height: 400), style: .plain)
        tableView.isScrollEnabled = false
        tableView.register(UINib(nibName: "TaskCell", bundle: nil), forCellReuseIdentifier: "TaskCell")
        tableView.rowHeight = 80
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        return tableView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        addTitle()
        addSubview(tableView)
    }
    
    var tasks:[Task] = [Task]()
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addTitle() {
        let titleView = UIView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 34))
        titleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleViewDidClick)))
        titleView.isUserInteractionEnabled = true
        let iconView = UIImageView(image: UIImage(named: "history"))
        titleView.addSubview(iconView)
        let titleLabel = UILabel()
        titleLabel.text = "Historical task".localized
        titleLabel.textColor = ColorA
        titleLabel.font = Font18
        titleView.addSubview(titleLabel)
        let moreBtn = UIImageView(image: UIImage(named: "more"))
        titleView.addSubview(moreBtn)
        iconView.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing)
            m.centerY.equalToSuperview()
            m.width.height.equalTo(15)
        }
        titleLabel.snp.makeConstraints { (m) in
            m.left.equalTo(iconView.snp.right).offset(12)
            m.centerY.equalToSuperview()
        }
        moreBtn.snp.makeConstraints { (m) in
            m.right.equalToSuperview().offset(-LRSpacing)
            m.width.equalTo(20)
            m.height.equalTo(20)
            m.centerY.equalToSuperview()
        }
        addSubview(titleView)
    }
    
    @objc func titleViewDidClick(){
        delegate?.taskModeDidClick()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tasks.count > 5 ? 5 : tasks.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell") as! TaskCell
        cell.selectionStyle = .none
        cell.isLast = indexPath.row == 4
        cell.task = tasks[indexPath.row]
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.taskDidClick(task: tasks[indexPath.row])
    }
    
    func refreshList(vpnIsOpen:Bool){
        tasks = Task.findAll(pageSize: 6, pageIndex: 0, orderBy: "id")
        //Task.findAll(orders: ["id":false])
        if vpnIsOpen {
            if tasks.count > 0 {
                tasks.removeFirst()
            }
        }
        tableView.reloadData()
    }
}
