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

func LogDebug(_ message: Any = "",
              file: String = #file,
              line: Int = #line,
              function: String = #function) {
        debugPrint( "***[debug]***-\(Thread.current)-\(name(of: file))[\(line)]:\(function) --> \(message)")
    if ASConfigration.logLevel == .debug {
        print( "***[debug]***-\(name(of: file))[\(line)]:\(function) --> \(message)")
    }
}

func LogInfo(_ message: Any = "",
             file: String = #file,
             line: Int = #line,
             function: String = #function) {
    if ASConfigration.logLevel.rawValue >= LogLevel.info.rawValue {
//        print( "***[info]***-\(name(of: file))[\(line)]:\(function) --> \(message)")
    }
    
}

func LogWarn(_ message: Any = "",
             file: String = #file,
             line: Int = #line,
             function: String = #function) {
    if ASConfigration.logLevel.rawValue >= LogLevel.warn.rawValue {
//        print( "***[warn]***-\(name(of: file))[\(line)]:\(function) --> \(message)")
    }
    
    
}

func LogError(_ message: Any = "",
              file: String = #file,
              line: Int = #line,
              function: String = #function) {
    print( "***[error]***-\(name(of: file))[\(line)]:\(function) --> \(message)")
    
}


private func name(of file:String) -> String {
    return URL(fileURLWithPath: file).lastPathComponent
}

//
//func LogDebug(_ message:  Any?) {
//    Log("***[debug]***\(String(describing: message))")
//}
//
//func LogDebug(_ format:  @autoclosure () -> String, _ arguments: CVarArg...) {
//    LogDebug(String(format: format(), arguments: arguments))
//}
//
//func LogInfo(_ message:  Any?) {
//    Log("***[info]***\(String(describing: message))")
//}
//
//func LogInfo(_ format:  @autoclosure () -> String, _ arguments: CVarArg...) {
//    LogInfo(String(format: format(), arguments: arguments))
//}
//
//func LogWarn(_ message:  Any?) {
//    Log("***[warn]***\(String(describing: message))")
//}
//
//func LogWarn(_ format:  @autoclosure () -> String, _ arguments: CVarArg...) {
//    LogWarn(String(format: format(), arguments: arguments))
//}
//
//func LogError(_ message:  Any?) {
//    Log("***[error]***\(String(describing: message))")
//}
//
//func LogError(_ format:  @autoclosure () -> String, _ arguments: CVarArg...) {
//    LogError(String(format: format(), arguments: arguments))
//}
//
