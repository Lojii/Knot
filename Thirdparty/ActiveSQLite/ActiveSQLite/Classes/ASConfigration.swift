//
//  ASConfigration.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 14/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite

//MARK: Custom Class
open class ASConfigration {
    public static var logLevel: LogLevel = .info
    
    private static var dbMap:Dictionary<String,Connection> = Dictionary<String,Connection>()
    
    private static var defaultDB:Connection!
    private static var defaultDBName:String?
    
    /// 创建数据库
    ///
    /// - Parameters:
    ///   - path: 文件路径
    ///   - name: 数据库名字
    ///   - isAutoCreate: 文件不存在时候，是否自动创建文件。默认true
        public static func setDB(path:String,name:String,isAutoCreate:Bool = true){
            
    //        guard dbMap[name] == nil else {
    //            return
    //        }
            if isAutoCreate || fileExists( path){
                do{
                    
                    let db = try Connection(path)
                    dbMap[name] = db
                }catch{
                    Log.e(error)
                }
               
            }
            
            //        #if DEBUG
            //            DBModel.db.trace{ debugPrint($0)}
            //        #endif
            
    //        if logLevel == .debug {
    //            db.trace{ print($0)}
    //        }
        }
    
        public static func setDefaultDB(path:String,name:String){
            
            guard dbMap[name] == nil else {
                return
            }
            
            defaultDBName = name
            
            do{
                let db = try Connection(path)
                dbMap[name] = db
                
                defaultDB = db
            }catch{
                Log.e(error)
            }
            
    //        if logLevel == .debug {
    //            db.trace{ print($0)}
    //        }
        }
        
        public static func getDefaultDB() throws -> Connection{
            if let db = defaultDB{
                return db
            }else{
                throw ASError.dbNotFound(dbName:defaultDBName ?? "默认数据库")
            }
        }
        
        public static func getDB(name:String) throws -> Connection{
            if let db = dbMap[name]{
                return db
            }else{
                throw ASError.dbNotFound(dbName:name)
            }
            
        }
        
        private static func fileExists(_ path:String) -> Bool{
            var isDir:ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if exists && !isDir.boolValue {
                return true
            }
            return false
        }
    
}



//var ExpressionKey: UInt8 = 0
//extension Expression {
//
//    var isDouble: Bool?  {
//        get {
//            return objc_getAssociatedObject(self, &ExpressionKey) as? Bool
//        }
//        set (v) {
//            objc_setAssociatedObject(self, &ExpressionKey, v, .OBJC_ASSOCIATION_ASSIGN)
//        }
//    }
//
//    public init(_ template: String, isDouble:Bool? = false) {
//        self.init(template,[nil])
//        self.isDouble = isDouble
//    }
//
//    public init(_ template: String, _ bindings: [Binding?],_ isDouble:Bool? = false) {
//        self.template = template
//        self.bindings = bindings
//        self.isDouble = isDouble
//    }
//
//}

//public protocol ExpressionType : Expressible { // extensions cannot have inheritance clauses
//
//    associatedtype UnderlyingType = Void
//
//    var template: String { get }
//    var bindings: [Binding?] { get }
//
//    init(_ template: String, _ bindings: [Binding?])
//
//}

/*

//MARK: -- custom types
// date -- string
extension Date: Value {
    class var declaredDatatype: String {
        return String.declaredDatatype
    }
    class func fromDatatypeValue(stringValue: String) -> Date {
        return SQLDateFormatter.dateFromString(stringValue)!
    }
    var datatypeValue: String {
        return SQLDateFormatter.stringFromDate(self)
    }
}

let SQLDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    formatter.locale = Locale(localeIdentifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(forSecondsFromGMT: 0)
    return formatter
}()




/*
//MARK: -- image
extension UIImage: Value {
    public class var declaredDatatype: String {
        return Blob.declaredDatatype
    }
    public class func fromDatatypeValue(blobValue: Blob) -> UIImage {
        return UIImage(data: Data.fromDatatypeValue(blobValue))!
    }
    public var datatypeValue: Blob {
        return UIImagePNGRepresentation(self)!.datatypeValue
    }
    
}

extension Query {
    subscript(column: Expression<UIImage>) -> Expression<UIImage> {
        return namespace(column)
    }
    subscript(column: Expression<UIImage?>) -> Expression<UIImage?> {
        return namespace(column)
    }
}

extension Row {
    subscript(column: Expression<UIImage>) -> UIImage {
        return get(column)
    }
    subscript(column: Expression<UIImage?>) -> UIImage? {
        return get(column)
    }
}

let avatar = Expression<UIImage?>("avatar")
users[avatar]           // failed to compile
users.namespace(avatar) // "users"."avatar"

let user = users.first!
user[avatar]            // failed to compile
user.get(avatar)        // UIImage?
*/
*/
