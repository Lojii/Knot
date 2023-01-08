//
//  Utils.swift
//  ActiveSQLiteTests
//
//  Created by kai zhou on 18/01/2018.
//  Copyright © 2018 wumingapie@gmail.com. All rights reserved.
//

import Foundation

let DBDefaultName = "TestDefaultDB"
let DBName2 = "OtherDB"

//default db path
public func getTestDBPath() -> String?{
 
    NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
    
    let documentDirPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    
    
    let fileManager = FileManager.default
    var isDir : ObjCBool = false
    let isExits = fileManager.fileExists(atPath: documentDirPath, isDirectory:&isDir)
    
    if isExits && !isDir.boolValue{
        fatalError("The dir is file，can not create dir.")
    }
    
    if !isExits {
        try! FileManager.default.createDirectory(atPath: documentDirPath, withIntermediateDirectories: true, attributes: nil)
        print("Create db dir success-\(documentDirPath)")
    }
    
    
    let dbPath = documentDirPath + "/ActiveSQLite.db"
    if !FileManager.default.fileExists(atPath: dbPath) {
        FileManager.default.createFile(atPath: dbPath, contents: nil, attributes: nil)
        print("Create db file success-\(dbPath)")
        
    }
    
    print(dbPath)
    return dbPath
}

public func getDB2Path() -> String{
    NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
    let documentDirPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
    
    
    let fileManager = FileManager.default
    var isDir : ObjCBool = false
    let isExits = fileManager.fileExists(atPath: documentDirPath, isDirectory:&isDir)
    
    if isExits && !isDir.boolValue{
        fatalError("The dir is file，can not create dir.")
    }
    
    if !isExits {
        try! FileManager.default.createDirectory(atPath: documentDirPath, withIntermediateDirectories: true, attributes: nil)
        print("Create db dir success-\(documentDirPath)")
    }
    
    let dbPath = documentDirPath + "/ActiveSQLite2.db"
    
    if !FileManager.default.fileExists(atPath: dbPath) {
        FileManager.default.createFile(atPath: dbPath, contents: nil, attributes: nil)
        print("Create db file success-\(dbPath)")
    }
    
    print(dbPath)
    return dbPath
}
