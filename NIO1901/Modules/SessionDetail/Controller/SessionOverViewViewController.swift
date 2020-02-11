//
//  SessionOverViewViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionOverViewViewController: UIViewController {

    var session:Session
    lazy var scrollView: UIScrollView = {
        let scrollViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let scrollView = UIScrollView(frame: scrollViewFrame)
        return scrollView
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
        setUI()
    }
    
    func setUI(){
        var offY:CGFloat = 0
        
        // http相关信息:协议、版本
        var infos = [[String:String]]()
        infos.append(["Protocol".localized:(session.schemes ?? "").uppercased()])
        infos.append(["Version".localized:session.reqHttpVersion ?? ""])
        infos.append(["Methods".localized:(session.methods ?? "").uppercased()])
        infos.append(["Code".localized:session.state ?? ""])
        infos.append(["User-Agent".localized:(session.target ?? "").urlDecoded()])
        infos.append(["Host":session.host ?? ""])
        infos.append(["Remote Address".localized:session.remoteAddress ?? ""])
        infos.append(["Local Address".localized:session.localAddress ?? ""])
//        infos.append(["Current state".localized:session.sstate ?? ""])
        let overView = SessionOverView(title: "Session".localized, details: infos)
        overView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: overView.itemHeight)
        scrollView.addSubview(overView)
        offY = offY + overView.frame.height
        // 数据相关
        var datas = [[String:String]]()
        datas.append(["Send data".localized:session.uploadTraffic.floatValue.bytesFormatting()])
        datas.append(["Receive data".localized:session.downloadFlow.floatValue.bytesFormatting()])
        let dataView = SessionOverView(title: "Data".localized, details: datas)
        dataView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: dataView.itemHeight)
        scrollView.addSubview(dataView)
        offY = offY + dataView.frame.height
        // 时间总览
        var times = [[String:String]]()
        var totalTime = (session.rspEndTime?.doubleValue ?? 0) - (session.startTime?.doubleValue ?? 0)
        if totalTime < 0 { totalTime = 0 }
        var totalTimeStr = String(format: "%.2f s", totalTime)//"\(totalTime)s"
        if totalTime < 1 {
            totalTimeStr = "\(Int(totalTime*1000)) ms"
        }
        let startTime = session.startTime?.doubleValue ?? 0
        let endTime = session.rspEndTime?.doubleValue ?? 0
        
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
        
//        // connectTime -> reqEndTime
//        times.append(["\("Request".localized):12:30:43.234-12:30:43.876":"345 \("ms".localized)"])
//        // reqEndTime -> rspEndTime
//        times.append(["\("Response".localized):12:30:44.076-12:30:45.366":"2.34 \("ms".localized)"])
        
        let timeView = SessionOverView(title: "\("Time".localized) \(dayStr)", details: times)
        timeView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: timeView.itemHeight)
        scrollView.addSubview(timeView)
        offY = offY + timeView.frame.height
        // 时间相关
        var subTimes = [[String:String]]()
        subTimes.append(["start":session.startTime?.stringValue ?? ""])     // 开始时间
        subTimes.append(["Request queue".localized:session.connectTime?.stringValue ?? ""])   // 开始建立连接时间
        subTimes.append(["Connection".localized:session.connectedTime?.stringValue ?? ""])   // 连接建立完成时间
        if session.schemes?.lowercased() == "https" {
            subTimes.append(["SSL/TLS":session.handshakeEndTime?.stringValue ?? ""])   // 握手结束时间
        }
        subTimes.append(["Send".localized:session.reqEndTime?.stringValue ?? ""])   // 发送完毕时间
        subTimes.append(["Waiting for response".localized:session.rspStartTime?.stringValue ?? ""])   // 开始接受响应时间
        subTimes.append(["Receive".localized:session.rspEndTime?.stringValue ?? ""])   // 接收结束时间
//        subTimes.append(["Close time".localized:session.endTime?.stringValue ?? ""])   // 接收结束时间
        let timesView = SessionTimeView(title: "Process".localized, times: subTimes)
        timesView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: timesView.itemHeight)
        scrollView.addSubview(timesView)
        offY = offY + timesView.frame.height
        //
        
        scrollView.contentSize = CGSize(width: 0, height: offY)
    }
    
}
