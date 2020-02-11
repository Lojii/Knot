//
//  String+filesize.swift
//  QoodCore
//
//  Created by peng(childhood@me.com) on 15/7/8.
//  Copyright (c) 2015年 xiaop. All rights reserved.
//

import Foundation

extension String{
    
    var NS: NSString { return (self as NSString)}
    func fileSize() -> UInt64{
        var fileSize : UInt64 = 0
        let attr:NSDictionary? = try! FileManager.default.attributesOfItem(atPath: self) as NSDictionary?
        if let _attr = attr {
            fileSize = _attr.fileSize();
        }
        return fileSize
    }
    func fileExist() -> Bool{
        return FileManager.default.fileExists(atPath:self)
    }
    func dirCreate() ->Bool{
        do {
            try FileManager.default.createDirectory(atPath: self, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch let e as NSError {
            NSLog("PacketTunnel error: %@", e.localizedDescription)
            return false
        }
    }
    func fileDelete()->Bool{
        do {
            try FileManager.default.removeItem(atPath: self)
            return true
        } catch _ {
            return false
        }
    }
}
public extension NSString{
    @objc func fileSize() -> UInt64{
        return ( self as String).fileSize()
    }
    @objc func fileExist() -> Bool{
        return (self as String).fileExist()
    }
    @objc func dirCreate() ->Bool{
        return (self as String).dirCreate()
    }
    @objc func fileDelete() ->Bool{
        return (self as String).fileDelete()
    }
}
