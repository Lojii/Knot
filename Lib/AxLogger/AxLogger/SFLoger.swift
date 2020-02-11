//
//  SFLoger.swift
//  AxLogger
//
//  Created by yarshure on 2017/6/20.
//  Copyright © 2017年 Kong XiangBo. All rights reserved.
//

import Foundation
import Darwin
func writeLog(_ __fd: Int32, _ __buf: UnsafeRawPointer!, _ __nbyte: Int) {
    write(__fd,__buf,__nbyte)
}
public class SFLogger:TextOutputStream {
    private var queue:DispatchQueue = DispatchQueue(label:"com.swift.logger")
    var fileURL:URL?
    var fd:Int32 = -1
    var isOpen:Bool = false
    var debugEnable:Bool = false
    lazy var df:DateFormatter={
        var f:DateFormatter=DateFormatter()
        //f.dateFormat="yyyy/MM/dd HH:mm:ss.SSS" file name contain date
        f.dateFormat="HH:mm:ss.SSS"
        return f
    }()
    public func openHandle(path:String) {
        
        fd = open(path,  O_WRONLY|O_CREAT|O_APPEND, 0o666)
        if fd > 0 {
            isOpen = true
        }
    }
    public func closeHandel(){
        close(fd)
        isOpen = false
    }
    public static var shared = SFLogger()
    public  func write(_ string: String){
        if isOpen {
            //write(fd, string, string.characters.count)
            queue.async {
                writeLog(self.fd, string, string.characters.count)
            }
            
        }
        
    }
    public  static var logleve:AxLoggerLevel = .Info
    
    static var logFormater = AxLogDefaultFormater()//= .Debug
    
    static public func log(_ msg:String,items: Any,level:AxLoggerLevel , category:String="default",file:String=#file,line:Int=#line,ud:[String:String]=[:],tags:[String]=[],time:Date=Date()){
        
        //other level
        
        if self.logFormater.debugEnable{
            SFLogger.shared.formate(msg: msg, items: items, level: level, category: category, file: file, line: line, ud: ud, tags: tags, time: time)
        }else {
            if level.rawValue <= self.logleve.rawValue {
                SFLogger.shared.formate(msg: msg, items: items, level: level, category: category, file: file, line: line, ud: ud, tags: tags, time: time)
            }
        }
    }
    func formate(msg:String,items: Any,level:AxLoggerLevel,category:String,file:String,line:Int,ud:[String:String],tags:[String],time:Date) {
        let timestr = self.df.string(from: time)
        
        //let filename = file.NS.lastPathComponent
        let processinfo = ProcessInfo.processInfo
        
        let threadid = pthread_mach_thread_np(pthread_self())
        #if os(iOS)
            let memory = memoryString(memoryUsed: reportMemoryUsed())
        #else
            let memory = memoryString(memoryUsed: reportMemoryUsed())
        #endif
        var logger = SFLogger.shared
        
        if debugEnable{
            print(timestr, level.description,"[", processinfo.processIdentifier, "]:\(threadid)"," mem:\(memory)", msg ,items,separator:" ", to: &logger) //\(category) \(filename)[\(line)]
        }else{
            print(timestr, level.description, " mem:\(memory)" , msg,items,separator:" ",to:&logger)
          
        }
        
        
    }
}
