//
//  Types.swift
//  ActiveSQLite
//
//  Created by kai zhou on 2018/8/13.
//  Copyright © 2018 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite

func isSupportTypes(_ value:Any)->Bool{
    let mir = Mirror(reflecting:value)
    
    switch mir.subjectType {
        
    case _ as String.Type,_ as String?.Type,
//         _ as Int64.Type,_ as Int64?.Type,
//         _ as Int.Type,_ as Int?.Type,
//         _ as Double.Type,_ as Double?.Type,
//         _ as Date.Type,_ as Date?.Type,
         _ as NSNumber.Type,_ as NSNumber?.Type,
         _ as NSDate.Type,_ as NSDate?.Type:
        return true
        
    default:
        return false
    }
}

extension NSNumber : SQLite.Value {
    public static var declaredDatatype: String {
        return Int64.declaredDatatype
    }
    
    public static func fromDatatypeValue(_ datatypeValue: Int64) -> NSNumber {
        return NSNumber(value:datatypeValue)
    }
    public var datatypeValue: Int64 {
        return Int64(truncating: self)
    }
    
}

//Date -- NSDate -> Int64. Date -> String
extension NSDate: SQLite.Value {
    public static var declaredDatatype: String {
        return Int64.declaredDatatype
    }
    public static func fromDatatypeValue(_ intValue: Int64) -> NSDate {
        return NSDate(timeIntervalSince1970: TimeInterval(intValue))
    }
    public var datatypeValue: Int64 {
        return  Int64(timeIntervalSince1970)
    }
}

extension Setter{
    static func generate(key:String,type:Any,value:Any?) -> Setter? {
        
        let mir = Mirror(reflecting:type)
        
        switch mir.subjectType {
            
        case _ as String.Type:
            return (Expression<String>(key) <- value as! String)
            
        case _ as String?.Type:
            if let v = value as? String {
                return (Expression<String?>(key) <- v)
            }else{
                return (Expression<String?>(key) <- nil)
            }
        
//        case _ as Int64.Type:
//            return (Expression<Int64>(key) <- value as! Int64)
//
//        case _ as Int64?.Type:
//            if let v = value as? Int64 {
//                return (Expression<Int64?>(key) <- v)
//            }else{
//                return (Expression<Int64?>(key) <- nil)
//            }
//
//        case _ as Int.Type:
//            return (Expression<Int>(key) <- value as! Int)
//
//        case _ as Int?.Type:
//            if let v = value as? Int {
//                return (Expression<Int?>(key) <- v)
//            }else{
//                return (Expression<Int?>(key) <- nil)
//            }
//
//        case _ as Double.Type:
//            return (Expression<Double>(key) <- value as! Double)
//
//        case _ as Double?.Type:
//            if let v = value as? Double {
//                return (Expression<Double?>(key) <- v)
//            }else{
//                return (Expression<Double?>(key) <- nil)
//            }

        case _ as Date.Type:
            return (Expression<Date>(key) <- value as! Date)
            
        case _ as Date?.Type:
            if let v = value as? Date {
                return (Expression<Date?>(key) <- v)
            }else{
                return (Expression<Date?>(key) <- nil)
            }
            
        case _ as NSNumber.Type:
            return (Expression<NSNumber>(key) <- value as! NSNumber)
            
        case _ as NSNumber?.Type:
            if let v = value as? NSNumber {
                return (Expression<NSNumber?>(key) <- v)
            }else{
                return (Expression<NSNumber?>(key) <- nil)
            }
            
        case _ as NSDate.Type:
            return (Expression<NSDate>(key) <- value as! NSDate)
        case _ as NSDate?.Type:
            
            if let v = value as? NSDate {
                return (Expression<NSDate?>(key) <- v)
            }else{
                return (Expression<NSDate?>(key) <- nil)
            }
            
        default:
            return nil
        }
    }
}

extension Expression{
    static func generate(key:String,type:Any,value:Any?) -> SQLite.Expression<Bool?>?{
        let mir = Mirror(reflecting:type)
        
        switch mir.subjectType {
            
        case _ as String.Type:
            return (Expression<Bool?>(Expression<String>(key) == value as! String))
        case _ as String?.Type:
            return (Expression<String?>(key) == value as! String?)
        
//        case _ as Int64.Type:
//            return (Expression<Bool?>(Expression<Int64>(key) == value as! Int64))
//        case _ as Int64?.Type:
//            return (Expression<Int64?>(key) == value as! Int64?)
//            
//        case _ as Int.Type:
//            return (Expression<Bool?>(Expression<Int>(key) == value as! Int))
//        case _ as Int?.Type:
//            return (Expression<Int?>(key) == value as! Int?)
//            
//        case _ as Double.Type:
//            return (Expression<Bool?>(Expression<Double>(key) == value as! Double))
//        case _ as Double?.Type:
//            return (Expression<Double?>(key) == value as! Double?)
//            
//        case _ as Date.Type:
//            return (Expression<Bool?>(Expression<Date>(key) == value as! Date))
//        case _ as Date?.Type:
//            return (Expression<Date?>(key) == value as! Date?)
            
            
        case _ as NSNumber.Type:
            return (Expression<Bool?>(Expression<NSNumber>(key) == value as! NSNumber))
        case _ as NSNumber?.Type:
            return (Expression<NSNumber?>(key) == value as? NSNumber)
            
        case _ as NSDate.Type:
            return (Expression<Bool?>(Expression<NSDate>(key) == value as! NSDate))
        case _ as NSDate?.Type:
            return (Expression<NSDate?>(key) == value as! NSDate?)
            
        default:
            return nil
        }
    }
}
