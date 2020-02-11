//
//  OutputUtil.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/2.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

enum OutputType {
    case HAR    // .har
    case CURL   // cUrl
    case URL    // url
    case DEL    // delete
}

let cachesFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).last
let outputFolder = cachesFolder!.appendingPathComponent("output")

class OutputUtil: NSObject {
    
    static func output(session:Session,type:OutputType,compeleHandle:@escaping ((String?) -> Void)){
//        if type == .URL {
//            let url = session.getFullUrl()
//            compeleHandle(url)
//        }
//        if type == .CURL {
//            let url = session.getCUrl()
//            compeleHandle(url)
//        }
//        if type == .HAR {
//            DispatchQueue.global().async {
//                output(sessions: [session], type: .HAR,compeleHandle: compeleHandle)
//            }
//        }
        DispatchQueue.global().async {
            output(sessions: [session], type: type,compeleHandle: compeleHandle)
        }
    }
    
    static func taskDoBatch(ids:[Int],type:OutputType,compeleHandle:@escaping ((String?) -> Void)) {
        DispatchQueue.global().async {
            let sessions = Task.findAll(taskIds:ids)
            if type == .DEL {
                if !Task.deleteAll(taskIds: ids) {
                    print("Delete Task Failure")
                }
            }
            output(sessions: sessions, type: type,compeleHandle: compeleHandle)
        }
    }
    
    static func output(ids:[Int],type:OutputType,compeleHandle:@escaping ((String?) -> Void)){
        DispatchQueue.global().async {
            let sessions = Session.findAll(ids:ids)
            output(sessions: sessions, type: type,compeleHandle: compeleHandle)
        }
    }
    
    static func deleteSessions(sessions:[Session],compeleHandle:@escaping ((String?) -> Void)){
        if sessions.count <= 0{
            DispatchQueue.main.async { compeleHandle("") }
            return
        }
        let fm = FileManager.default
        for s in sessions {
            let reqBodyPath = "\(MitmService.getStoreFolder())\(s.fileFolder ?? "error")/\(s.reqBody)"
            let rspBodyPath = "\(MitmService.getStoreFolder())\(s.fileFolder ?? "error")/\(s.rspBody)"
            try? s.delete()
            try? fm.removeItem(atPath: reqBodyPath)
            try? fm.removeItem(atPath: rspBodyPath)
        }
        DispatchQueue.main.async { compeleHandle("") }
    }
    
    static func output(sessions:[Session],type:OutputType,compeleHandle:@escaping ((String?) -> Void)) {
        
        // delete
        if type == .DEL {
            deleteSessions(sessions: sessions, compeleHandle: compeleHandle)
            return
        }
        // output
        if !createFolder(outputFolder) {
            DispatchQueue.main.async { compeleHandle(nil) }
            return
        }
        if sessions.count <= 0{
            DispatchQueue.main.async { compeleHandle("") }
            return
        }
        if type == .HAR {
            let har = HAR()
            for s in sessions { har.append(session: s) }
            if let jsonData = try? JSONEncoder().encode(har)  {
                let fileUrl = outputFolder.appendingPathComponent("NIO-\(Date().dateName).har")
                try? jsonData.write(to: fileUrl)
                DispatchQueue.main.async { compeleHandle(fileUrl.absoluteString) }
                return
            }
        }
        if type == .URL || type == .CURL {
            let fileUrl = outputFolder.appendingPathComponent("NIO-\(Date().dateName).\(type == .URL ? "url" : "curl").txt")
            if let filePath = fileUrl.absoluteString.components(separatedBy: "file://").last {
                if createFiles(filePath: filePath),let fileHandle = FileHandle(forWritingAtPath: filePath) {
                    for s in sessions {
                        let line = "\(type == .URL ? s.getFullUrl() : s.getCUrl())\n\n"
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(line.data(using: .utf8) ?? Data())
                    }
                    fileHandle.closeFile()
                }
                DispatchQueue.main.async { compeleHandle(fileUrl.absoluteString) }
                return
            }
        }
        
        DispatchQueue.main.async { compeleHandle(nil) }
    }
    
    static func createFiles(filePath:String) -> Bool{
        let fileManager = FileManager.default
        var isDir : ObjCBool = false
        let isExits = fileManager.fileExists(atPath: filePath, isDirectory: &isDir)
        if !isExits {
            return fileManager.createFile(atPath: filePath, contents: nil, attributes: nil)
        }else{
            return true
        }
    }
    
    static func createFolder(_ folder:URL) -> Bool{
        let fileManager = FileManager.default
        var isDir : ObjCBool = false
        let path = folder.absoluteString.components(separatedBy: "file://").last
        let isExits = fileManager.fileExists(atPath: path ?? folder.absoluteString, isDirectory: &isDir)
        if !isExits || !isDir.boolValue {
            do{
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
            }catch{
                return false
            }
        }
        return true
    }
    
    static func createOutputFile(_ filePath:URL) -> Bool{
        if !createFolder(outputFolder) {
            return false
        }
        let fileManager = FileManager.default
        let path = filePath.absoluteString.components(separatedBy: "file://").last ?? filePath.absoluteString
        let isExits = fileManager.fileExists(atPath: path, isDirectory: nil)
        if !isExits {
            return fileManager.createFile(atPath: path, contents: nil, attributes: nil)
        }
        return true
    }
}

extension Session {
    func getCUrl() -> String {
        var curl = "curl"
        if schemes?.lowercased() == "https" {
            curl.append(" -k")
        }
        if let m = methods {
            curl.append(" -X \(m.uppercased())")
        }
        let headerDic = [String:String].fromJson(reqHeads ?? "")
        for kv in headerDic {
            let hstr = "\"\(kv.key): \(kv.value)\""
            curl.append(" -H \(hstr)")
        }
        if let reqData = getDecodedBody(true) {
            if let reqBodyStr = String(data: reqData, encoding: .utf8) {
                let str = "\(reqBodyStr.debugDescription)"
                curl.append(" -d \(str)")
            }else{
                let str = "'@\(reqBody)'"
                curl.append(" --data-binary \(str)")
            }
        }
        curl.append(" \"\(getFullUrl())\"")
        return curl
    }
}
