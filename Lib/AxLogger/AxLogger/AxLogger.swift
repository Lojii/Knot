//
//  Logger.swift
//  QoodMessageProcessor
//
//  Created by xiaop on 15/6/23.
//  Copyright (c) 2015年 xiaop. All rights reserved.
//

import Foundation
@objc public enum AxLoggerLevel:Int,CustomStringConvertible{
    // 调整优先级
    case Error = 0
    case Warning = 1
    case Info = 2
    case Notify = 3
    case Trace = 4
    case Verbose = 5
    case Debug = 6
    public var description: String {
        switch self {
        case .Error: return "Error"
        case .Warning: return "Warning"
        case .Info: return "Info"
        case .Notify: return "Notify"
            
        case .Trace: return "Trace"
        case .Verbose: return "Verbose"
        case .Debug: return "Debug"
        }
    }
}

func reopenStdout(baseURL:URL){
    let url = baseURL.appendingPathComponent("stdout.log")
    let path = url.path
        let x = path.cString(using: String.Encoding.utf8)
        freopen(x!, "w", stdout)
        freopen(x!, "w", stderr)
        
}


protocol AxLogFormater{
    func formate(msg:String,level:AxLoggerLevel,category:String,file:String,line:Int,ud:[String:String],tags:[String],time:Date) -> String
}
func memoryUsed() -> String {
    let mem =  reportMemoryUsed()
    return memoryString(memoryUsed: mem)

}
func memoryString(memoryUsed:UInt64) ->String {
    let f = Float(memoryUsed)
    if memoryUsed < 1024 {
        return "\(memoryUsed) Bytes"
    }else if memoryUsed >=  1024 &&  memoryUsed <  1024*1024 {
        
        return  String(format: "%.2f KB", f/1024.0)
    }
    return String(format: "%.2f MB", f/1024.0/1024.0)
    
}
class AxLogDefaultFormater:AxLogFormater{
   

    lazy var df:DateFormatter={
        var f:DateFormatter=DateFormatter()
        //f.dateFormat="yyyy/MM/dd HH:mm:ss.SSS" file name contain date
        f.dateFormat="HH:mm:ss.SSS"
        return f
    }()
    var debugEnable:Bool = false
    
    func formate(msg:String,level:AxLoggerLevel,category:String,file:String,line:Int,ud:[String:String],tags:[String],time:Date) -> String{
        let timestr =  String.init(format: "%.3f", Date().timeIntervalSince1970) //self.df.string(from: time)
        
        //let filename = file.NS.lastPathComponent
        let processinfo = ProcessInfo.processInfo
        
        let threadid = pthread_mach_thread_np(pthread_self())
        #if os(iOS)
            let memory = memoryString(memoryUsed: reportMemoryUsed())
            #else
            let memory = memoryString(memoryUsed: reportMemoryUsed())
            #endif
        var  result:String = ""
//        if level == .Debug {
//            
//            let fn = file.components(separatedBy: "/").last
//            result = "\(timestr) \(level.description) [\(processinfo.processIdentifier):\(threadid)] mem:\(memory) \(fn!)[\(line)] \(msg) " //\(category)
//        }else {
//            
//        }
        if debugEnable{
            result = "\(timestr) \(level.description) [\(processinfo.processIdentifier):\(threadid)] mem:\(memory) \n\(msg) " //\(category) \(filename)[\(line)]
        }else{
            result = "\(timestr) \(level.description) mem:\(memory) \n\(msg)  "
        }
        
        return result
    }
    
}

public class AxLogger:NSObject{
    
    public static var applog:AxLogFile = {
        var logger = AxLogFile(name: "applog",ext:"log", dir:"")
        //logger.enableConsole(true)
        return logger
    }()
    //let client = asl_open(nil, "com.apple.console", 0)
    static func closeLogging(){
        //log("\(applog) close logging file")
        applog.closeLog()
    }
    static func resetLogFile(){
        //applog.log("resetLogFile 000")
        applog.closeLog()
        applog.reopen()
        //applog.log("resetLogFile 111")
    }
    public static func openLogging(_ baseURL:URL, date:Date,debug:Bool=false){
        let f:DateFormatter=DateFormatter()
        //f.dateFormat="yyyy/MM/dd HH:mm:ss.SSS" file name contain date
        f.dateFormat="yyyy_MM_dd_HH_mm_ss"
        let session = f.string(from: date)
        let u  = baseURL.appendingPathComponent("Log/" + session + "/")
        
        //applog will create log dir
        applog.openLogging(date: date ,path:u.path)
        
        if debug{
            reopenStdout(baseURL: u)
        }
    }
    public  static var logleve:AxLoggerLevel = .Info
    
    static var logFormater = AxLogDefaultFormater()//= .Debug
    @objc static public func log(_ msg:String,level:AxLoggerLevel , category:String="default",file:String=#file,line:Int=#line,ud:[String:String]=[:],tags:[String]=[],time:Date=Date()){
        
        //other level
        
        if self.logFormater.debugEnable{
            applog.log(msg: self.logFormater.formate(msg: msg, level: level, category: category, file: file, line: line, ud: ud, tags: tags, time: time))
        }else {
            if level.rawValue <= self.logleve.rawValue {
                applog.log(msg: self.logFormater.formate(msg: msg, level: level, category: category, file: file, line: line, ud: ud, tags: tags, time: time))
            }
        }
    }
    
    @objc static public func enableConsole(enable:Bool){
        //applog.enableConsole(enable)
    }

}

typealias Qlog = AxLogger

