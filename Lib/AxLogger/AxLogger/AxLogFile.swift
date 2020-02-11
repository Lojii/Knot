//
//  AxLogger.swift
//  AxLogger
//
//  Created by xiaop on 15/6/25.
//  Copyright (c) 2015年 xiaop. All rights reserved.
//

import Foundation

typealias AxLoggerCompleteCb = () -> Void

public class AxLogFile{
    private var queue:DispatchQueue?
    var name:String
    var ext:String
    private var logctx:ylog_context = ylog_context()
    var dir:String
    var logpath:String
    var filemgr = FileManager.default
    var logPathDateFormater:DateFormatter = {
        var df = DateFormatter()
        df.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        return df
    }()
    var logDateFormater:DateFormatter = {
        var df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return df
    }()
    init(name:String,ext:String,dir:String){
        let date = Date()
        self.name=logPathDateFormater.string(from: date) //68K memory used
        self.dir = dir
        self.ext = ext
        
        //if !self.dir.fileExist(){_ = self.dir.dirCreate()}
        self.queue=DispatchQueue(label:"axlogger.queue.\(name)")
        self.logpath = "\(self.dir)/\(self.name).\(ext)"
        //self.openLog()
    }
    internal func openLogging(date:Date,path:String){
        if logctx.isopen == 0 {
            self.dir = path
            //NSLog("reopen logfile %@",self.dir)
            self.name=logPathDateFormater.string(from: date)
            if !self.dir.fileExist(){_ = self.dir.dirCreate()}
            
            //self.queue = dispatch_queue_create("axlogger.queue.\(name)", DISPATCH_QUEUE_SERIAL)
            self.logpath = "\(self.dir)/\(self.name).\(ext)"
            self.openLog()
        } else {
            //NSLog("logfile have opened")
        }
        
    }
    private func exec(block:@escaping () -> Void){
        self.queue!.async(execute: block)
        
    }
    private func openLog(){
        ylog_open(&self.logctx,self.logpath)
    }
    internal func reopen(){
        
    }
    internal func closeLog(){
        ylog_close(&self.logctx)
    }
    deinit{
        self.closeLog()
    }
    private func rollPath(dir:String) -> String{
        let timestr = self.logPathDateFormater.string(from: Date())
        let randomNum = arc4random()
        return "\(dir)/\(self.name)_archive_\(timestr)_\(randomNum).\(self.ext)"
    }
    //public functions
    func enableConsole(enable:Bool){
        self.exec{
            self.logctx.enableconsole = enable ? 1 : 0
        }
    }
    func rollLog(dir:String,complete:@escaping AxLoggerCompleteCb){
        self.exec{
            if !dir.fileExist(){_ = dir.dirCreate()}
            //check file size
            if self.logpath.fileSize() > 0{ //max than 1k
                //close log
                self.closeLog()
                do {
                    //move log
                    try self.filemgr.moveItem(atPath: self.logpath, toPath: self.rollPath(dir: dir))
                } catch _ {
                }
                //open log
                self.openLog()
            }
            //complete
            complete()
        }
    }
    func rawLog(data:Data){
        self.exec{
            //ylog_raw(&self.logctx, UnsafePointer<Int8>(data.bytes), UInt32(data.length))
            _ =  data.withUnsafeBytes({ (ptr:UnsafeRawBufferPointer) in
                let p = ptr.bindMemory(to: Int8.self)
                ylog_log0(&self.logctx, p.baseAddress)
            })
        }
    }
    func log(msg:String){
        self.exec{
            if let cString = msg.cString(using: .utf8){
                ylog_log0(&self.logctx, cString)
            }else {
                ylog_log0(&self.logctx, "Error:convert to cString error!!!!!!!!!!!!")
            }
        }
    }
}
