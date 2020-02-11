//
//  ProxyContext.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/20.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import NIOSSL

class ProxyContext: NSObject {
    
    var cert:NIOSSLCertificate?
    var pkey:NIOSSLPrivateKey?
    
    var _clientChannel:Channel?
    var clientChannel:Channel?{
        set{
            _clientChannel = newValue
            _clientChannel?.closeFuture.whenComplete({ (R) in
                switch R{
                case .failure(let error):
                    print("******\(self.request?.host ?? "") clientChannel close error ! \(error.localizedDescription)")
                    break
                case .success(_):
                    self.session.outState = "\(self.session.outState ?? "")->close"
                    self.session.endTime = NSNumber(value: Date().timeIntervalSince1970)
                    try? self.session.saveToDB()
                    self.serverChannel?.close(mode: .all, promise: nil)
                    break
                }
            })
        }
        get{
            return _clientChannel
        }
    }
    
    var _serverChannel:Channel?
    var serverChannel:Channel?{
        set{
            _serverChannel = newValue
            _serverChannel?.closeFuture.whenComplete({ (R) in
                switch R{
                case .failure(let error):
                    print("******\(self.request?.host ?? "") serverChannel close error ! \(error.localizedDescription)")
                    break
                case .success(_):
                    self.session.inState = "\(self.session.inState ?? "")->close"
                    self.session.endTime = NSNumber(value: Date().timeIntervalSince1970)
                    try? self.session.saveToDB()
                    // 发送实时状态数据到主App
                    if !self.session.ignore {
                        self.task.sendInfo(url: self.session.getFullUrl(), uploadTraffic: self.session.uploadTraffic, downloadFlow: self.session.downloadFlow)
                    }
                    break
                }
            })
        }
        get{
            return _serverChannel
        }
    }
    
    var request:NetRequest?
    var isHttp:Bool
    var isSSL:Bool = false
    
    var task:Task
    var session:Session
    
    init(isHttp:Bool = false, task:Task) {
        self.isHttp = isHttp
        self.task = task
        self.session = Session.newSession(task)
        session.inState = "open"
        session.startTime = NSNumber(value: Date().timeIntervalSince1970)
    }
    
    /*
     
     context.channel.closeFuture.whenComplete { (R) in
     print("context:\(context):closed")
     }
     */
}
