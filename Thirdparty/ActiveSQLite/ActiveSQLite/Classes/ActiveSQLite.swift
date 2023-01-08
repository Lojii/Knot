//
//  ActiveSQLite.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou  on 04/07/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite

public  func save(db:Connection? = nil, _ block: @escaping ()throws -> Void,
                        completion: ((_ error:Error?)->Void)? = nil) -> Void  {
    
    do{
        
        
        let excuteDB = (db != nil ? db! : try ASConfigration.getDefaultDB())
        
        try excuteDB.transaction {
            try block()
        }
        
        Log.i("Transcation success")
        completion?(nil)
    }catch{
        Log.e("Transcation failure:\(error)")
        completion?(error)
    }
    
}


public  func saveAsync(db:Connection? = nil, _ block: @escaping ()throws -> Void,
                             completion: ((_ error:Error?)->Void)? = nil) -> Void  {
    
    DispatchQueue.global().async {
        
        do{
            let excuteDB = (db != nil ? db! : try ASConfigration.getDefaultDB())
            
            //            try excuteDB.transaction(.exclusive, block: {
            //                try block()
            //            })
            try excuteDB.transaction {
                try block()
            }
            
            Log.i("Transcation success")
            
            DispatchQueue.main.async {
                completion?(nil)
            }
            
        }catch{
            Log.e("Transcation failure:\(error)")
            
            DispatchQueue.main.async {
                completion?(error)
            }
        }
        
    }
    
}

public extension Connection {
    //userVersion Database
    var userVersion: Int32 {
        get { return Int32(try! scalar("PRAGMA user_version") as! Int64)}
        set { try! run("PRAGMA user_version = \(newValue)") }
    }
}


