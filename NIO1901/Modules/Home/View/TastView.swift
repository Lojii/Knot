//
//  TastView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/28.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class TastView: UIView, UITableViewDelegate, UITableViewDataSource {
    
    var _task:Task?
    var task:Task?{
        set{
            _task = newValue
            updateUI()
        }
        get{
            return _task
        }
    }
    
    var timer:Timer?
    
    lazy var tableView: UITableView = {
        let tableView = UITableView(frame: CGRect(x: 0, y: 34, width: SCREENWIDTH, height: 80), style: .plain)
        tableView.isScrollEnabled = false
        tableView.register(UINib(nibName: "TaskCell", bundle: nil), forCellReuseIdentifier: "TaskCell")
        tableView.rowHeight = 80
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        return tableView
    }()
    
    lazy var timeLabel: UILabel = {
        let timeLabel = UILabel()
        timeLabel.font = Font16
        timeLabel.textColor = ColorR
        return timeLabel
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        addTitle()
        addSubview(tableView)
        addTimer()
    }
    
    func addTimer(){
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(timeCalculate), userInfo: nil, repeats: true)
        if timer != nil {
            RunLoop.current.add(timer!, forMode: .common)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addTitle() {
        let titleView = UIView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 34))
//        titleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleViewDidClick)))
        titleView.isUserInteractionEnabled = true
        let iconView = UIImageView(image: UIImage(named: "current"))
        titleView.addSubview(iconView)
        let titleLabel = UILabel()
        titleLabel.text = "The current task".localized
        titleLabel.textColor = ColorA
        titleLabel.font = Font18
        titleView.addSubview(titleLabel)
        iconView.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing)
            m.centerY.equalToSuperview()
            m.width.height.equalTo(15)
        }
        titleLabel.snp.makeConstraints { (m) in
            m.left.equalTo(iconView.snp.right).offset(12)
            m.centerY.equalToSuperview()
        }
        titleView.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { (m) in
            m.centerY.equalTo(titleLabel)
            m.left.equalTo(titleLabel.snp.right)
        }
        addSubview(titleView)
    }
    
    @objc func timeCalculate(){
//        lsof.getlsof()
        if let st = task?.startTime {
            let startDate = Date(timeIntervalSince1970: TimeInterval(truncating: st))
            let cps = Calendar.current.dateComponents([.day,.hour,.minute,.second], from: startDate, to: Date())
            var timeStr = ""
            if let day = cps.day, day > 0 {
                timeStr = timeStr + "\(day)\("day".localized)"
            }
            if let hour = cps.hour, hour > 0 {
                timeStr = timeStr + "\(hour):"//\("hours".localized)"
            }
            if let minute = cps.minute, minute > 0 {
                timeStr = timeStr + "\(minute):"//\("minute".localized)"
            }
            if let second = cps.second, second > 0 {
                timeStr = timeStr + "\(second)"//\("seconds".localized)"
            }
            timeLabel.text = "(\(timeStr))"
        }
    }
    
    @objc func titleViewDidClick(){
        let urls = ["https://www.baidu.com","https://www.jianshu.com"]
        DispatchQueue.global().async {
            for url in urls {
                sleep(1)
                let u = URL(string: url)!
                let request: URLRequest = URLRequest(url: u)
                let session = URLSession(configuration: URLSessionConfiguration.default)
                let dataTask: URLSessionDataTask = session.dataTask(with: request) { (data, response, error) in
                    if(error == nil){
                        print("got success!",url)
                    }else{
                        print("got error:%@",error?.localizedDescription ?? "null",url)
                    }
                }
                dataTask.resume()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return task == nil ? 0 : 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell") as! TaskCell
        cell.selectionStyle = .none
        cell.isLast = true
        cell.task = task
        return cell
    }
    
    func updateUI(){
        if task == nil {
            // 停止计时
            timer?.invalidate()
        }else{
            // 重新开始计时
            timer?.invalidate()
            addTimer()
            timer?.fire()
        }
        tableView.reloadData()
    }
    
    func updateTask(dic:[String:String]){
        if _task != nil {
            let count = _task!.interceptCount.intValue + 1
            _task?.interceptCount = NSNumber(integerLiteral: count)
            if let uploadTrafficStr = dic["uploadTraffic"], let intValue = Int(uploadTrafficStr) {
                let sum = _task!.uploadTraffic.intValue + intValue
                _task?.uploadTraffic = NSNumber(integerLiteral: sum)
            }
            if let downloadFlowStr = dic["downloadFlow"], let intValue = Int(downloadFlowStr) {
                let sum = _task!.downloadFlow.intValue + intValue
                _task?.downloadFlow = NSNumber(integerLiteral: sum)
            }
        }
        tableView.reloadData()
    }
}
