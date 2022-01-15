//
//  ASProtocol.swift
//  ActiveSQLite
//
//  Created by kai zhou on 2018/5/28.
//  Copyright © 2018 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite

public protocol ASProtocol:class {
//    static var dbName:String?{get}
//    static var db:Connection{get}
//    //'public' modifier cannot be used in protocols
//    static var CREATE_AT_KEY:String{get}
//    static var created_at:Expression<NSNumber>{get}
//
//    static var isSaveDefaulttimestamp:Bool{get}
//    static var nameOfTable: String{get}
//    static func getTable() -> Table
    
//    init()
    //default argument not permitted in protocol method
//    static func findAllinAS(_ predicate: SQLite.Expression<Bool?>?,orders: [Expressible]?)->Array<ASModel>
}

public extension ASProtocol where Self:ASModel{
    
    
//    public static var dbName:String?{
//        return nil
//    }
//
//    static var db:Connection{
//        get{
//            if let name = dbName {
//                return ASConfigration.getDB(name: name)
//            }else{
//                return ASConfigration.getDefaultDB()
//            }
//
//        }
//    }
//
//    public static var CREATE_AT_KEY:String{
//        return  "created_at"
//    }
//    public static var created_at:Expression<NSNumber>{
//        return Expression<Int64>(CREATE_AT_KEY)
//    }
//
//    public static var isSaveDefaulttimestamp:Bool {
//        return false
//    }
//
//    public static var nameOfTable: String{
//        return NSStringFromClass(self).components(separatedBy: ".").last!
//    }
//
//    public static func getTable() -> Table{
//        return Table(nameOfTable)
//    }
    
}
