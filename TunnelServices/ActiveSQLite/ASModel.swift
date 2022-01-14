//
//  ASModel.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 05/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite


/*
 Model Type    SQLite.swift Type      SQLite Type
 NSNumber    Int64(Int,Bool)         INTEGER
 NSNumber    Double                  REAL
 String      String                  TEXT
 nil         nil                     NULL
 --------    SQLite.Blob†             BLOB
 NSDate      Int64                   INTEGER
 */


@objcMembers open class ASModel:NSObject,ASProtocol{
    
    @objc public internal(set) var id:NSNumber? //id primary key
    @objc public var created_at:NSNumber = NSNumber(value:Date().timeIntervalSince1970 * 1000) //Create Time, ms
    @objc public var updated_at:NSNumber = NSNumber(value:Date().timeIntervalSince1970 * 1000) // Update Time，ms
    
    public static var id = Expression<NSNumber>(PRIMARY_KEY)
    public static var created_at = Expression<NSNumber>(CREATE_AT_KEY)
    public static var updated_at = Expression<NSNumber>(UPDATE_AT_KEY)
    
    public static var CREATE_AT_KEY:String = "created_at"
    public static var UPDATE_AT_KEY:String = "updated_at"
    
    internal var _query:QueryType? //TODO:codable
    
    required override public init() {
        super.init()
    }
    
    public convenience init(id:Int64) {
        self.init()
        self.id = NSNumber(value: id)
    }
    
    //MARK: override
    open class var dbName:String?{
        return nil
    }
    
    open class var nameOfTable: String{
        return NSStringFromClass(self).components(separatedBy: ".").last!
    }
    
    open class var PRIMARY_KEY:String{
        return "id"
    }
    
    open class var isSaveDefaulttimestamp:Bool {
        return false
    }
    
    open func doubleTypes() -> [String]{
        return [String]()
    }
    
    open func mapper() -> [String:String]{
        return [String:String]()
    }
    
    open func transientTypes() -> [String]{
        return [String]()
    }
    
    
    //MARK: - getter setter
    //T? == Optional<T>
    //T! == ImplicitlyUnwrappedOptional<T>
    public var created_date:NSDate! {
        set{
            created_at = NSNumber(value:Int64(newValue.timeIntervalSince1970 * 1000))
        }
        get{
            return NSDate(timeIntervalSince1970: TimeInterval(created_at.int64Value/1000))
        }
    }
    public var updated_date:NSDate! {
        set{
            updated_at = NSNumber(value:Int64(newValue.timeIntervalSince1970 * 1000))
        }
        get{
            return NSDate(timeIntervalSince1970: TimeInterval(updated_at.int64Value/1000))
        }
    }
    
    open var nameOfTable:String{
        get{
            return type(of: self).nameOfTable
        }
    }
    
    public class func getDB() throws -> Connection{
//        get{
            if let name = dbName {
                return try ASConfigration.getDB(name: name)
            }else{
                return try ASConfigration.getDefaultDB()
            }
            
//        }
    }
    
    public func getDB() throws -> Connection{
    //        get{
        return try type(of: self).getDB()
    //        }
    }
    public class func getTable() -> Table{
        return Table(nameOfTable)
    }

    public func getTable() -> Table{
        return type(of: self).getTable()
    }

    @objc open override func setValue(_ value: Any?, forKey key: String) {
        super.setValue(value, forKey: key)
    }

    @objc open override func value(forKey key: String) -> Any? {
        return super.value(forKey: key)
    }

    //MARK: - utils


    override open var description: String{
        var des = "**DB Model**：" + super.description + "->"
        //        var des = "**DB Model**" + NSStringFromClass(type(of: self)) + "-> "

        for case let (attribute?, column?, value) in recursionProperties(){
            //            if attribute == "created_at" || attribute == "updated_at" {
            //                des += "\(attribute) = \((value as! NSNumber).int64Value), "
            //            }else{
            des += "\(attribute) = \(value), "
            //            }
            
        }
        return des
    }
    
}


//public extension ASModel{

//MARK: - Generic Type
//    func findAll<T:ASModel>(_ predicate: SQLite.Expression<Bool>, toT t:T)->Array<T>{
//
//        return findAll(Expression<Bool?>(predicate),toT:t)
//    }
//
//    func findAll<T:ASModel>(_ predicate: SQLite.Expression<Bool?>, toT t:T)->Array<T>{
//
//        var results:[T] = [T]()
//
//        var query = getTable().where(predicate)
//        if type(of: self).isSaveDefaulttimestamp{
//            query = query.order(type(of: self).created_at.desc)
//        }
//
//
//        do{
//            for result in try T.db.prepare(query) {
//
//                let model = T()
//                model.buildFromRow(row: result)
//
//                results.append(model)
//            }
//        }catch{
//            Log.e("Find all for \(nameOfTable) failure: \(error)")
//        }
//
//
//        return results
//    }
//
//    func findAll<T:ASModel>(_ predicate: SQLite.Expression<Bool?>)->Array<T>{
//
//        var results:[T] = [T]()
//
//        var query = getTable().where(predicate)
//
//        if type(of: self).isSaveDefaulttimestamp {
//            query = query.order(type(of: self).created_at.desc)
//        }
//
//
//        do{
//            for result in try T.db.prepare(query) {
//
//                let model = T()
//                model.buildFromRow(row: result)
//
//                results.append(model)
//            }
//        }catch{
//            Log.e("Find all for \(nameOfTable) failure: \(error)")
//        }
//
//
//        return results
//    }

//    internal func findAll<T:ASModel>(_ predicate: SQLite.Expression<Bool?>) -> [T] where T : ASModel{
//
//        var results:[T] = [T]()
//
//        var query = getTable().where(predicate)
//
//        if type(of: self).isSaveDefaulttimestamp {
//            query = query.order(type(of: self).created_at.desc)
//        }
//
//        do{
//            for result in try T.db.prepare(query) {
//
//                let model = T()
//                model.buildFromRow(row: result)
//
//                results.append(model)
//            }
//        }catch{
//            Log.e("Find all for \(nameOfTable) failure: \(error)")
//        }
//
//
//        return results
//    }


//}

