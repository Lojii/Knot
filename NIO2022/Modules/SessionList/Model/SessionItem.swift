//
//  SessionItem.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/12.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan

class SessionItem {
    
    static let TopSpacint:CGFloat = 5
    static let BottomSpacint:CGFloat = 5+1
    
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
        uri = session.uri
        let host = session.host
        if !uri.starts(with: "/") {
            let us = uri.components(separatedBy: host)
            uri = us.last ?? session.uri 
        }
        let uus = uri.components(separatedBy: "?")
        if uus.count >= 2 {
            uri = uus[0]
        }
        uriH = uri.textHeight(font: Font14, fixedWidth: uriW)
        if uriH > "xxx".textHeight(font: Font14, fixedWidth: uriW) * 4 {
            uriH = "xxx".textHeight(font: Font14, fixedWidth: uriW) * 4
        }

        methodsH = session.method.textHeight(font: Font14, fixedWidth: 1000)
        methodsW = session.method.textWidth(font: Font14) + 5
        if session.suffix != "" {
            type = session.suffix
            typeW = type.textWidth(font: Font14) + 8
            if ImageTypes.contains(type.lowercased()) {
                isImage = true
            }
        }
        state = session.rsp_state
        if state == "" {
            state = "unfinished".localized
        }
        stateW = state.textWidth(font: Font14) + 8
        hostW = session.host.textWidth(font: Font14)

        if let shortTarget = session.req_target.components(separatedBy: " (").first {
            targetW = shortTarget.urlDecoded().textWidth(font: Font13)
        }
        let fullSrcHost = session.srchost_str + ":" + session.srcport_str
        let fullDstHost = session.dsthost_str + ":" + session.dstport_str
        localW = fullSrcHost.textWidth(font: Font13)
        remoteW = fullDstHost.textWidth(font: Font13)

        let stime = session.dns_time_s
        let sDate = Date.init(timeIntervalSince1970: stime.doubleValue)
        time = sDate.CurrentStingTimeForCell
        timeW = time.textWidth(font: Font12)
        
        up = session.out_bytes.floatValue.bytesFormatting()
        down = session.in_bytes.floatValue.bytesFormatting()
        upW = up.textWidth(font: Font12)
        downW = down.textWidth(font: Font12)

        sessionCellHeight = SessionItem.TopSpacint + uriH + methodsH + targetH + timeH + SessionItem.BottomSpacint
    }
}
