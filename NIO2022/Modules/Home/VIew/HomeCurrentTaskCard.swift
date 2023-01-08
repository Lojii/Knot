//
//  HomeCurrentTaskCard.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/16.
//

import UIKit
import SnapKit
import NIOMan

class HomeCurrentTaskCard: HomeCard {

    var didClick: ((Task?) -> Void)?
    
    var titleLabel:UILabel! // 当前任务
    var timeLabel:UILabel!   // 时间
    var tableView:UITableView! //
    var outLabel:UILabel!   // 上传
    var inLabel:UILabel!    // 下载
    var numLabel:UILabel!   // 会话数
    
    var rows:[String] = []
    var task:Task?
    var timer:Timer?
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func cardDidClick() -> Void {
        didClick?(task)
    }
    
    func setUI() -> Void {
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardDidClick)))
        
        titleLabel = UILabel()
        titleLabel.font = Font18
        titleLabel.textColor = ColorB
        titleLabel.numberOfLines = 0
        titleLabel.text = "The current task".localized
        addSubview(titleLabel)
        
        timeLabel = UILabel()
        timeLabel.font = Font18
        timeLabel.textColor = ColorR
        timeLabel.numberOfLines = 0
        timeLabel.text = "00:00:00"
        timeLabel.textAlignment = .right
        addSubview(timeLabel)
        
        tableView = UITableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.isUserInteractionEnabled = false
        tableView.register(HomeUrlCell.self, forCellReuseIdentifier: "HomeUrlCell")
        addSubview(tableView)
        
        outLabel = UILabel()
        outLabel.font = Font16
        outLabel.textColor = ColorB
        outLabel.numberOfLines = 0
        outLabel.text = "\("Up".localized):0 M"
        addSubview(outLabel)
        
        inLabel = UILabel()
        inLabel.font = Font16
        inLabel.textColor = ColorB
        inLabel.numberOfLines = 0
        inLabel.text = "\("Down".localized):0 M"
        addSubview(inLabel)
        
        numLabel = UILabel()
//        numLabel.font = Font16
//        numLabel.textColor = ColorB
//        numLabel.numberOfLines = 0
//        numLabel.text = "\("Count".localized):623753"
//        numLabel.textAlignment = .right
//        addSubview(numLabel)
        // 当前任务
        titleLabel.snp.makeConstraints { (m) in
            m.left.equalTo(snp.left).offset(HomeCard.LRMargin)
            m.top.equalTo(snp.top).offset(HomeCard.TBMargin)
        }
        // 12:00:00
        timeLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel.snp.centerY)
            make.right.equalTo(snp.right).offset(-HomeCard.LRMargin)
        }
        // 上传：10m
        outLabel.snp.makeConstraints { make in
            make.bottom.equalTo(snp.bottom).offset(-HomeCard.TBMargin)
            make.left.equalTo(snp.left).offset(HomeCard.LRMargin)
        }
        // 下载：110m
        inLabel.snp.makeConstraints { make in
            make.centerY.equalTo(outLabel.snp.centerY)
            make.left.equalTo(outLabel.snp.right).offset(15)
        }
        // 会话数：23423
//        numLabel.snp.makeConstraints { make in
//            make.centerY.equalTo(outLabel.snp.centerY)
//            make.right.equalTo(snp.right).offset(-HomeCard.LRMargin)
//        }
        //
        tableView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(13)
            make.width.equalTo(snp.width)
            make.centerY.equalTo(snp.centerY)
            make.bottom.equalTo(inLabel.snp.top).offset(-13)
        }
    }
    
    func dismiss(){
        isHidden = true
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
        task = nil
        rows = []
        tableView.reloadData()
    }
    // 查询数据库中，该task最新的50条
    func loadInitDatas(){
        let reqLines = Session.findReqLines(task_id: task!.task_id)
        rows = reqLines
        tableView.reloadData()
    }
    // 更新流量等数据
    func updateNums(){
        inLabel.text = "\("Down".localized):\(task!.in_bytes.floatValue.bytesFormatting())"
        outLabel.text = "\("Up".localized):\(task!.out_bytes.floatValue.bytesFormatting())"
    }
    // 外部调用，实时刷新
    func updateDatas(dic:[String:Any]?){
        isHidden = false
        if task != nil {
            guard let newData = dic else { return }
            let conn_count = newData["conn_count"] as? Int ?? 0
            let in_bytes = newData["in_bytes"] as? Double ?? 0
            let out_bytes = newData["out_bytes"] as? Double ?? 0
            task!.conn_count = NSNumber(value: conn_count)
            task!.in_bytes = NSNumber(value: in_bytes)
            task!.out_bytes = NSNumber(value: out_bytes)
            // upUI
            let req_line = newData["req_line"] as? String ?? ""
            if req_line != "" {
                // add line
                rows.insert(req_line, at: 0)//append(req_line)
                tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .top)
            }
            updateNums()
        }else{
            // 初始化
            let gud = UserDefaults(suiteName: GROUPNAME)
            if let currentTaskId = gud?.value(forKey: CURRENTTASKID),let currentTask = Task.findOne(currentTaskId as! String) {
                task = currentTask
                addTimer()
                loadInitDatas() // 加载初始数据
                updateNums()
            }
        }
    }
    
    func addTimer(){
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(timeCalculate), userInfo: nil, repeats: true)
        if timer != nil {
            RunLoop.current.add(timer!, forMode: .common)
        }
    }
    
    @objc func timeCalculate(){
        if let st = task?.start_time {
            let startDate = Date(timeIntervalSince1970: TimeInterval(truncating: st))
            let cps = Calendar.current.dateComponents([.day,.hour,.minute,.second], from: startDate, to: Date())
            var timeStr = ""
            if let day = cps.day, day > 0 {
                timeStr = timeStr + "\(day)\("day".localized)"
            }
            if let hour = cps.hour, hour >= 0 {
                let hourStr = hour < 10 ? "0\(hour)" : "\(hour)"
                timeStr = timeStr + "\(hourStr):"//\("hours".localized)"
            }
            if let minute = cps.minute, minute >= 0 {
                let minuteStr = minute < 10 ? "0\(minute)" : "\(minute)"
                timeStr = timeStr + "\(minuteStr):"//\("minute".localized)"
            }
            if let second = cps.second, second >= 0 {
                let secondStr = second < 10 ? "0\(second)" : "\(second)"
                timeStr = timeStr + secondStr
            }
            timeLabel.text = "\(timeStr)"
        }
    }
    
}

extension HomeCurrentTaskCard: UITableViewDelegate, UITableViewDataSource{
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HomeUrlCell") as! HomeUrlCell
        cell.nameLabel.text = rows[indexPath.row]
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 30
    }
    
}

class HomeUrlCell:UITableViewCell {
    
    var nameLabel:UILabel
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.nameLabel = UILabel()
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    func setupUI(){
        nameLabel.textColor = ColorC
        nameLabel.font = Font14
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { (m) in
            m.centerY.equalTo(contentView.snp.centerY)
            m.left.equalToSuperview().offset(HomeCard.LRMargin)
            m.right.equalToSuperview().offset(-HomeCard.LRMargin)
        }
        
        let line = UIView()
        line.backgroundColor = ColorE
        contentView.addSubview(line)
        line.snp.makeConstraints { (m) in
            m.left.equalTo(contentView.snp.left).offset(LRSpacing)
            m.right.equalTo(contentView.snp.right).offset(-LRSpacing)
            m.bottom.equalToSuperview()
            m.height.equalTo(1)
        }
    }
}
