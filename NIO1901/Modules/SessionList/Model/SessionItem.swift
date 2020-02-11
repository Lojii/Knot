//
//  SessionItem.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/12.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionItem {
    
    static let TopSpacint:CGFloat = 5
    static let BottomSpacint:CGFloat = 5
    
    var _session:Session!
    var session:Session!{
        set{
            _session = newValue
            calculateCell()
        }
        get{
            return _session
        }
    }
    var sessionCellHeight:CGFloat = 0
    
    var uriH:CGFloat = 0
    var uriW:CGFloat = SCREENWIDTH - LRSpacing * 2
    
    var methodsH:CGFloat = "xxx".textWidth(font: Font14)
    var methodsW:CGFloat = 0
    var typeW:CGFloat = 0
    var stateW:CGFloat = 0
    var hostW:CGFloat = 0
    var targetH:CGFloat = "xxx".textWidth(font: Font13)
    var targetW:CGFloat = 0
    var localW:CGFloat = 0
    var remoteW:CGFloat = 0
    var timeH:CGFloat = "xxx".textWidth(font: Font12)
    var timeW:CGFloat = 0
    var upW:CGFloat = 0
    var downW:CGFloat = 0
    
    var uri:String = ""
    var type:String = ""
    var state:String = ""
    var time:String = ""
    var up:String = ""
    var down:String = ""
    var localAddress:String = ""
    var remoteAddress:String = ""
    
    var isImage:Bool = false
    var isVideo:Bool = false
    
    init(_ session:Session) {
        _session = session
        calculateCell()
    }
    
    public func calculateCell(){
        uri = session.uri ?? ""
        if !uri.starts(with: "/"), let host = session.host {
            let us = uri.components(separatedBy: host)
            uri = us.last ?? session.uri ?? ""
        }
        let uus = uri.components(separatedBy: "?")
        if uus.count >= 2 {
            uri = uus[0]
        }
        uriH = uri.textHeight(font: Font14, fixedWidth: uriW)
        if uriH > "xxx".textHeight(font: Font14, fixedWidth: uriW) * 4 {
            uriH = "xxx".textHeight(font: Font14, fixedWidth: uriW) * 4
        }
        
        methodsH = session.methods?.textHeight(font: Font14, fixedWidth: 1000) ?? 0
        methodsW = (session.methods?.textWidth(font: Font14) ?? 0) + 5
        if session.suffix != "" {
            type = session.suffix
//            let ss = type.components(separatedBy: "/")
//            if ss.count >= 2{ type = ss[1] }
//            let cs = type.components(separatedBy: ";")
//            if cs.count >= 2{ type = cs[0] }
            typeW = type.textWidth(font: Font14) + 8
            if ImageTypes.contains(type.lowercased()) {
                isImage = true
            }
        }
        if let sta = session.state, sta != "" {
            state = sta
        }else{
            state = "unfinished".localized
        }
        stateW = state.textWidth(font: Font14) + 8
        hostW = session.host?.textWidth(font: Font14) ?? 0

        targetW = session.target?.urlDecoded().textWidth(font: Font13) ?? 0
        localW = session.localAddress?.textWidth(font: Font13) ?? 0
        remoteW = session.remoteAddress?.textWidth(font: Font13) ?? 0
        
        if let stime = session.startTime {
            let sDate = Date.init(timeIntervalSince1970: stime.doubleValue)
            time = sDate.CurrentStingTimeForCell
            timeW = time.textWidth(font: Font12)
        }
        up = session.uploadTraffic.floatValue.bytesFormatting()
        down = session.downloadFlow.floatValue.bytesFormatting()
        upW = up.textWidth(font: Font12)
        downW = down.textWidth(font: Font12)
        
        sessionCellHeight = SessionItem.TopSpacint + uriH + methodsH + targetH + timeH + SessionItem.BottomSpacint
    }
}
