//
//  NetAddress.swift
//  NIO1901
//
//  Created by Lojii on 2019/1/17.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class NetAddress: NSObject {
    public var host:String = ""
    public var port:Int? = nil
    
    public init(host:String ,port: Int) {
        self.host = host
        self.port = port
    }
    
    public func isEqual(address: NetAddress?) -> Bool {
        if(address == nil){
            return false
        }
        if(host == address!.host && port == address!.port){
            return true
        }
        return false
    }

}
