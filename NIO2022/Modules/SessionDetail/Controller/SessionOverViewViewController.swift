//
//  SessionOverViewViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan

class SessionOverViewViewController: UIViewController {

    var session:Session
    lazy var scrollView: UIScrollView = {
        let scrollViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let scrollView = UIScrollView(frame: scrollViewFrame)
        return scrollView
    }()
    
    lazy var stackView:UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        return stackView
    }()
    
    init(_ session:Session) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        setUI()
    }
    
    override func viewDidLayoutSubviews(){
       super.viewDidLayoutSubviews()
       scrollView.contentSize = CGSize(width: stackView.frame.width, height: stackView.frame.height + 34)
    }
    
    func setUI(){
        var lastV:UIView?
        // http相关信息:协议、版本
        var infos = [[String:String]]()
        infos.append(["Protocol".localized:(session.schemes).uppercased()])
        infos.append(["Version".localized:session.version])
        infos.append(["Methods".localized:(session.method).uppercased()])
        infos.append(["Code".localized:session.rsp_state])
        infos.append(["User-Agent".localized:(session.req_target).urlDecoded()])
        infos.append(["Host":session.host])
        infos.append(["Remote Address".localized:session.dsthost_str+":"+session.dstport_str])
        infos.append(["Local Address".localized:session.srchost_str+":"+session.srcport_str])
        let overView = SessionOverView(title: "Session".localized, details: infos)
        stackView.addArrangedSubview(overView)
        lastV = overView
        
        // 数据相关
        var datas = [[String:String]]()
        datas.append(["Send data".localized:session.out_bytes.floatValue.bytesFormatting()])
        datas.append(["Receive data".localized:session.in_bytes.floatValue.bytesFormatting()])
        let dataView = SessionOverView(title: "Data".localized, details: datas)
        stackView.addArrangedSubview(dataView)
        lastV = dataView

        // 时间总览
        var times = [[String:String]]()
        var totalTime = session.receive_e.doubleValue - session.dns_time_s.doubleValue
        if totalTime < 0 { totalTime = 0 }
        var totalTimeStr = String(format: "%.2f s", totalTime)//"\(totalTime)s"
        if totalTime < 1 { totalTimeStr = "\(Int(totalTime*1000)) ms" }
        let startTime = session.dns_time_s.doubleValue
        let endTime = session.receive_e.doubleValue
        var timeStr = ""
        var dayStr = ""
        if startTime > 0 , endTime > 0 {
            let startDate = Date(timeIntervalSince1970: startTime)
            let startTimeStr = startDate.CurrentStingTimeForCell
            timeStr = ":\(startTimeStr)-"
            dayStr = "(\(startDate.MMDDStr))"
        }
        if endTime > 0{
            let endDate = Date(timeIntervalSince1970: endTime)
            let endTimeStr = endDate.CurrentStingTimeForCell
            timeStr = timeStr + endTimeStr
        }
        times.append(["Total time".localized+timeStr:totalTimeStr])
        let timeView = SessionOverView(title: "\("Time".localized) \(dayStr)", details: times)
        stackView.addArrangedSubview(timeView)
        lastV = timeView
//
        // 时间相关
        var subTimes = [[String:String]]()
        subTimes.append(["start":session.dns_time_s.stringValue])     // 开始时间
        subTimes.append(["DNS":session.connect_s.stringValue])   // 开始建立连接时间
        subTimes.append(["Connection".localized:session.send_s.stringValue])   // 连接建立完成时间
        subTimes.append(["Send".localized:session.send_e.stringValue])   // 发送完毕时间
        subTimes.append(["Waiting for response".localized:session.receive_s.stringValue])   // 开始接受响应时间
        subTimes.append(["Receive".localized:session.receive_e.stringValue])   // 接收结束时间
        let timesView = SessionTimeView(title: "Process".localized, times: subTimes)
        stackView.addArrangedSubview(timesView)
        lastV = timesView
        //
        stackView.snp.makeConstraints { make in
            make.top.equalTo(scrollView.snp_top)
            make.left.equalTo(scrollView.snp_left)
//            make.right.equalTo(scrollView.snp_right)
            make.width.equalTo(SCREENWIDTH)
            if lastV != nil {
                make.bottom.equalTo(lastV!.snp_bottom)
            }
        }
        
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
}
