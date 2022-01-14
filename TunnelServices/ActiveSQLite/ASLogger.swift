//
//  ASLogger.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 04/07/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Foundation

public enum LogLevel:Int {
    case debug = 1,info,warn,error
}

public class Log{
    static func d(_ message: Any = "",
                  file: String = #file,
                  line: Int = #line,
                  function: String = #function) {
        //    debugPrint( "***[debug]***-\(Thread.current)-\(name(of: file))[\(line)]:\(function) --> \(message)")
        if ASConfigration.logLevel == .debug {
            print( "***[debug]***-\(name(of: file))[\(line)]:\(function) --> \(message)")
        }
    }

    static func i(_ message: Any = "",
                 file: String = #file,
                 line: Int = #line,
                 function: String = #function) {
        if ASConfigration.logLevel.rawValue >= LogLevel.info.rawValue {
            print( "***[info]***-\(name(of: file))[\(line)]:\(function) --> \(message)")
        }
        
    }

    static func w(_ message: Any = "",
                 file: String = #file,
                 line: Int = #line,
                 function: String = #function) {
        if ASConfigration.logLevel.rawValue >= LogLevel.warn.rawValue {
            print( "***[warn]***-\(name(of: file))[\(line)]:\(function) --> \(message)")
        }
        
        
    }

    static func e(_ message: Any = "",
                  file: String = #file,
                  line: Int = #line,
                  function: String = #function) {
        print( "***[error]***-\(name(of: file))[\(line)]:\(function) --> \(message)")
        
    }
    
    static func name(of file:String) -> String {
        return URL(fileURLWithPath: file).lastPathComponent
    }
}

/*
import CocoaLumberjack

public class Log{
    public static func config(level:DDLogLevel? = .info, timeFormatter:(()->String)? = nil){
        DDTTYLogger.sharedInstance?.logFormatter = LoggerFormatter(timeFormatter)
        DDLog.add(DDTTYLogger.sharedInstance as! DDLogger, with: level ?? .info) // TTY = Xcode console

        //    DDTTYLogger.sharedInstance.colorsEnabled = true
        //    DDLog.add(DDASLLogger.sharedInstance) // ASL = Apple System Logs

        let fileLogger = DDFileLogger()
        fileLogger.logFormatter = LoggerFormatter(timeFormatter)
        fileLogger.rollingFrequency = TimeInterval(60*60*4) //4小时一个日志文件
        fileLogger.logFileManager.maximumNumberOfLogFiles = 18 //3天一共产生18个文件
        DDLog.add(fileLogger, with: .info)

    }


    /// 日志级别：verbose
    public static func v(_ message:  Any?,tag:String? = nil,
                         file: StaticString = #file, line: UInt = #line,function: StaticString = #function) {

        v(format:"%@", String(describing: message),tag:tag,file:file,line:line,function:function)
    }
    public static func v(_ message:  String,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        v(format:"%@", message,tag:tag,file:file,line:line,function:function)
    }

    public static func v(_ message:  String ...,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        v(format:"%@", message.reduce("",{$0 + $1 + " "}),tag:tag,file:file,line:line,function:function)
    }

    public static func v(format:  @autoclosure () -> String, _ arguments: CVarArg...,tag:String? = nil,
                         file: StaticString = #file, line: UInt = #line,function: StaticString = #function) {

        DDLogVerbose((tag != nil ? "tag:\(tag!) ": "") + String(format: format(), arguments: arguments),file:file,function:function, line:line)
    }

    /// 日志级别：debug
    public static func d(_ message:  Any?,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        d(format:"%@", String(describing: message),tag:tag,file:file,line:line,function:function)
    }
    public static func d(_ message:  String,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        d(format:"%@", message,tag:tag,file:file,line:line,function:function)
    }

    public static func d(_ message:  String ...,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        d(format:"%@", message.reduce("",{$0 + $1 + " "}),tag:tag,file:file,line:line,function:function)
    }

    public static func d(format:  @autoclosure () -> String, _ arguments: CVarArg...,tag:String? = nil,
                        file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {
        DDLogDebug((tag != nil ? "tag:\(tag!) ": "") + String(format: format(), arguments: arguments),file:file,function:function, line:line)
    }


    /// 日志级别：info
    public static func i(_ message:  Any?,tag: String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {
        i(format:"%@", String(describing: message),tag:tag,file:file,line:line,function:function)
    }

    public static func i(_ message:  String,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        i(format:"%@", message,tag:tag,file:file,line:line,function:function)
    }

    public static func i(_ message:  String ..., tag: String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        i(format:"%@", message.reduce("",{$0 + $1 + " "}),tag:tag,file:file,line:line,function:function)
    }


    public static func i(format:  @autoclosure () -> String, _ arguments: CVarArg...,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        DDLogInfo((tag != nil ? "tag:\(tag!) ": "") + String(format: format(), arguments: arguments),file:file,function:function, line:line)
    }

    /// 日志级别：warn
    public static func w(_ message:  Any?,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {
        w(format:"%@", String(describing: message),tag:tag,file:file,line:line,function:function)
    }

    public static func w(_ message:  String,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        w(format:"%@", message,tag:tag,file:file,line:line,function:function)
    }

    public static func w(_ message:  String ...,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        w(format:"%@", message.reduce("",{$0 + $1 + " "}),tag:tag,file:file,line:line,function:function)
    }

    public static func w(format:  @autoclosure () -> String, _ arguments: CVarArg...,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        DDLogWarn((tag != nil ? "tag:\(tag!) ": "") + String(format: format(), arguments: arguments),file:file,function:function, line:line)
    }

    /// 日志级别：error
    public static func e(_ message: Any?,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        e(format:"%@", String(describing: message),tag:tag,file:file,line:line,function:function)
    }

    public static func e(_ message:  String,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        e(format:"%@", message,tag:tag,file:file,line:line,function:function)
    }

    public static func e(_ message:  String ...,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        e(format:"%@", message.reduce("",{$0 + $1 + " "}),tag:tag,file:file,line:line,function:function)
    }

    public static func e(format:  @autoclosure () -> String, _ arguments: CVarArg...,tag:String? = nil,
                         file: StaticString = #file,line: UInt = #line,function: StaticString = #function) {

        DDLogError((tag != nil ? "tag:\(tag!) ": "") + String(format: format(), arguments: arguments),file:file,function:function, line:line)
    }

    static func name(of file:String) -> String {
        return URL(fileURLWithPath: file).lastPathComponent
    }

}

class LoggerFormatter:NSObject, DDLogFormatter {

    var timeFormatter:(()->String)?
    init(_ timeFormatter:(()->String)? = nil) {
        self.timeFormatter = timeFormatter
        super.init()
    }

    func format(message logMessage: DDLogMessage) -> String? {
        var logLevel = ""
        switch logMessage.flag {
        case .verbose:
            logLevel = "v"
            break
        case .debug:
            logLevel = "d"
            break
        case .info:
            logLevel = "i"
            break
        case .warning:
            logLevel = "w"
            break
        case .error:
            logLevel = "e"
            break
        default:
            logLevel = ""
            break
        }

        let timestamp = timeFormatter != nil ? timeFormatter!() : String(describing: logMessage.timestamp)
        return "\(timestamp) \(logMessage.fileName)[\(logMessage.function ?? ""):\(logMessage.line)] ***[\(logLevel)]*** \(logMessage.message)"

    }

}
*/
