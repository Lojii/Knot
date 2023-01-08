//
//  OutputUtil.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/2.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan

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
        
        DispatchQueue.global().async {
            output(sessions: [session], type: type,compeleHandle: compeleHandle)
        }
    }
    
    static func taskDoBatch(ids:[Int],type:OutputType,compeleHandle:@escaping ((String?) -> Void)) {
        
        DispatchQueue.global().async {
            let task_ids = Task.findAllTaskIds(ids:ids)
            let sessions = Task.findAll(taskIds:task_ids)
            output(sessions: sessions, type: type) { file in
                if type == .DEL {
                    if Task.deleteAll(taskIds: task_ids) {
                        // 移除task文件夹
                        let fm = FileManager.default
                        for task_id in task_ids {
                            if let taskPath = NIOMan.LogsPath()?.appendingPathComponent(task_id).path.components(separatedBy: "file://").last {
                                try? fm.removeItem(atPath: taskPath)
                            }
                        }
                        compeleHandle("")
                        return
                    }else{
                        print("Delete Task Failure")
                    }
                }
                compeleHandle(file)
            }
        }
    }
    
    static func output(ids:[Int],type:OutputType,compeleHandle:@escaping ((String?) -> Void)){
        let block = {
            DispatchQueue.global().async {
                let sessions = Session.findAll(ids:ids)
                output(sessions: sessions, type: type,compeleHandle: compeleHandle)
            }
        }
//        if !KnotPurchase.hasProduct(.HappyKnot) { // 未购买
//            KnotPurchase.showStoreView(.HappyKnot) { res in
//
//            }
//            compeleHandle(nil)
//            return
//        }
        block()
    }
    
    static func deleteSessions(sessions:[Session],compeleHandle:@escaping ((String?) -> Void)){
        if sessions.count <= 0{
            DispatchQueue.main.async { compeleHandle("") }
            return
        }
        let fm = FileManager.default
        for s in sessions {
            // 移除 .line .head .body .req .rsp
            if let reqPath = NIOMan.LogsPath()!.appendingPathComponent(s.req_path).path.components(separatedBy: "file://").last {
                try? fm.removeItem(atPath: reqPath + ".line")
                try? fm.removeItem(atPath: reqPath + ".head")
                try? fm.removeItem(atPath: reqPath + ".body")
                try? fm.removeItem(atPath: reqPath)
            }
            if let rspPath = NIOMan.LogsPath()!.appendingPathComponent(s.rsp_path).path.components(separatedBy: "file://").last {
                try? fm.removeItem(atPath: rspPath + ".line")
                try? fm.removeItem(atPath: rspPath + ".head")
                try? fm.removeItem(atPath: rspPath + ".body")
                try? fm.removeItem(atPath: rspPath)
            }
            try? s.delete()
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
            // 有一个写一个，不能全部处理完再写入，不然可能会超出内存处理极限
            // 创建文件，写入头，循环写入entry，最后写入尾
            let fileUrl = outputFolder.appendingPathComponent("Knot-\(Date().dateName).har")
            do {
                let harStartStr = """
                {"log": { "version": "1.2", "creator":{ "name": "Knot", "version": "1.0" },"entries": [
                """
                try harStartStr.data(using: .utf8)?.write(to: fileUrl)
                let fileHandle = try FileHandle(forUpdating:fileUrl)
                for i in 0..<sessions.count {
                    let s = sessions[i]
                    if s.host == "" { continue }
                    fileHandle.seekToEndOfFile()
                    if let entry = HAR.entry(session: s) {
                        if var jsonData = try? JSONEncoder().encode(entry)  {
                            if i < sessions.count - 1 {
                                jsonData.append(",".data(using: .utf8)!)
                            }
                            fileHandle.write(jsonData)
                        }
                    }
                }
                fileHandle.seekToEndOfFile()
                fileHandle.write("]}}".data(using: .utf8)!)
                fileHandle.closeFile()
            } catch {
                print("HAR文件写入失败！")
                DispatchQueue.main.async { compeleHandle(nil) }
                return
            }
            DispatchQueue.main.async { compeleHandle(fileUrl.absoluteString) }
            return
        }
        if type == .URL || type == .CURL {
            let fileUrl = outputFolder.appendingPathComponent("Knot-\(Date().dateName).\(type == .URL ? "url" : "curl").txt")
            if let filePath = fileUrl.absoluteString.components(separatedBy: "file://").last {
                if createFiles(filePath: filePath),let fileHandle = FileHandle(forWritingAtPath: filePath) {
                    for s in sessions {
                        let line = "\(type == .URL ? s.fullUrl() : s.getCUrl())\n\n"
                        if line == "\n\n" { continue }
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
        if host == "" { return "" }
        var curl = "curl"
        if schemes.lowercased() == "https" {
            curl.append(" -k")
        }
        curl.append(" -X \(method.uppercased())")
        _ = syncParse()
        if let headerDic = head(true) {
            for kv in headerDic {
                let hstr = "\"\(kv.key): \(kv.value)\""
                curl.append(" -H \(hstr)")
            }
        }
        if let reqBodyPath = body(true) {
            let reqBodyUrl = URL(fileURLWithPath: "file://\(reqBodyPath)")
            if let reqBody = try? Data(contentsOf: reqBodyUrl) {
                if let bodyStr = String(data: reqBody, encoding: .utf8) {
                    curl.append(" -d \(bodyStr)")
                }else{
                    let str = "'@\(reqBody)'"
                    curl.append(" --data-binary \(str)")
                }
            }
        }
        curl.append(" \"\(fullUrl())\"")
        return curl
    }
}
