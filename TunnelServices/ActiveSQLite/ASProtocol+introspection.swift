//
//  ASProtocolQuery.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 08/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite


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
    
    //MARK: - Comment
    internal func buildExpression(_ attribute: String, value:Any?)->SQLite.Expression<Bool?>?{
        
        return buildExpression([attribute:value])
        
    }
    
    internal func buildExpression(_ attributeAndValueDic:Dictionary<String,Any?>)->SQLite.Expression<Bool?>?{
        
        
        var expressions = Array<SQLite.Expression<Bool?>>()
        
        for case let (attribute?,column?, v) in recursionProperties() {
            
            if attributeAndValueDic.keys.contains(attribute) {
                
                let value = attributeAndValueDic[attribute]
                
                if attribute == primaryKeyAttributeName {
                    expressions.append(Expression<Bool?>(Expression<NSNumber>(column) == value as! NSNumber))
                    continue
                }
                
                let mir = Mirror(reflecting:v)
                
                switch mir.subjectType {
                    
                case _ as String.Type:
                    expressions.append(Expression<Bool?>(Expression<String>(column) == value as! String))
                case _ as String?.Type:
                    expressions.append(Expression<String?>(column) == value as! String?)
                    
                case _ as NSNumber.Type:
                    
                    if self.doubleTypes().contains(attribute) {
                        expressions.append(Expression<Bool?>(Expression<Double>(column) == value as! Double))
                    }else{
                        expressions.append(Expression<Bool?>(Expression<NSNumber>(column) == value as! NSNumber))
                    }
                    
                case _ as NSNumber?.Type:
                    
                    if self.doubleTypes().contains(attribute) {
                        expressions.append(Expression<Double?>(column) == value as? Double)
                        
                    }else{
                        expressions.append(Expression<NSNumber?>(column) == value as? NSNumber)
                        
                    }
                    
                case _ as NSDate.Type:
                    expressions.append(Expression<Bool?>(Expression<NSDate>(column) == value as! NSDate))
                case _ as NSDate?.Type:
                    expressions.append(Expression<NSDate?>(column) == value as! NSDate?)
                    
                default: break
                    
                }
                
//                if let expression = Expression<Bool?>.generate(key: column, type: v, value: value!) {
//                    expressions.append(expression)
//                }
                
            }
            
        }
        
        if expressions.count > 1 {
            var exp = expressions.first!
            for i in 1..<expressions.count {
                exp = exp && expressions[i]
            }
            return exp
        }else{
            return expressions.first
        }
        
    }
    
    internal func buildExpressiblesForOrder(_ attributeAndAscDic:Dictionary<String,Bool>)->[Expressible]{
        
        
        var expressibles = [Expressible]()
        
        for case let (attribute?,column?, v) in recursionProperties() {
            
            if attributeAndAscDic.keys.contains(attribute) {
                
                let isAsc = attributeAndAscDic[attribute]!
                let mir = Mirror(reflecting:v)
                
                switch mir.subjectType {
                    
                case _ as String.Type:
                    expressibles.append((isAsc ? Expression<String>(column).asc : Expression<String>(column).desc))
                case _ as String?.Type:
                    expressibles.append((isAsc ? Expression<String?>(column).asc : Expression<String?>(column).desc))
                    
                case _ as NSNumber.Type:
                    
                    if self.doubleTypes().contains(attribute) {
                        expressibles.append((isAsc ? Expression<Double>(column).asc : Expression<Double>(column).desc))
                    }else{
                        expressibles.append((isAsc ? Expression<NSNumber>(column).asc : Expression<NSNumber>(column).desc))
                    }
                    
                case _ as NSNumber?.Type:
                    
                    if self.doubleTypes().contains(attribute) {
                        expressibles.append((isAsc ? Expression<Double?>(column).asc : Expression<Double?>(column).desc))
                        
                    }else{
                        expressibles.append((isAsc ? Expression<NSNumber?>(column).asc : Expression<NSNumber?>(column).desc))
                        
                    }
                    
                case _ as NSDate.Type:
                    expressibles.append((isAsc ? Expression<NSDate>(column).asc : Expression<NSDate>(column).desc))
                case _ as NSDate?.Type:
                    expressibles.append((isAsc ? Expression<NSDate?>(column).asc : Expression<NSDate?>(column).desc))
                    
                default: break
                    
                }
                
            }
            
        }
        return expressibles
        
    }
    
    //MARK: - Build
    internal func buildFromRow(row:Row){

        for case let (attribute?,column?, value) in recursionProperties() {
            //            let s = "Attribute ：\(attribute) Value：\(value),   " +
            //                    "Mirror: \(Mirror(reflecting:value)),  " +
            //                    "Mirror.subjectType: \(Mirror(reflecting:value).subjectType),    " +
            //                    "Mirror.displayStyle: \(String(describing: Mirror(reflecting:value).displayStyle))"
            //            LogDebug(s)
            //            LogDebug("assign Value-\(value) to \(attribute)-attribute of \(nameOfTable). ")

            if attribute == primaryKeyAttributeName {
                let v = try! row.get(Expression<NSNumber>(column))
                setValue(v, forKey: attribute)
                continue
            }
            
            let mir = Mirror(reflecting:value)

            switch mir.subjectType {

            case _ as String.Type:
                setValue(row[Expression<String>(column)], forKey: attribute)

            case _ as String?.Type:
                if let v = row[Expression<String?>(column)] {
                    setValue(v, forKey: attribute)
                }else{
                    setValue(nil, forKey: attribute)
                }


            case _ as NSNumber.Type:

                if self.doubleTypes().contains(attribute) {
                    setValue(NSNumber(value:try! row.get(Expression<Double>(column))) , forKey: attribute)
                }else{

                    let v = try! row.get(Expression<NSNumber>(column))
                    setValue(v, forKey: attribute)

                }

            case _ as NSNumber?.Type:

                if self.doubleTypes().contains(attribute) {
                    if let v = try! row.get(Expression<Double?>(column)) {
                        setValue(NSNumber(value:v), forKey: attribute)
                    }
                }else{
                    if let v = try! row.get(Expression<NSNumber?>(column)) {
                        setValue(v, forKey: attribute)
                    }else{
                        setValue(nil, forKey: attribute)
                    }
                }

            case _ as NSDate.Type:
                setValue(try! row.get(Expression<NSDate>(column)), forKey: attribute)

            case _ as NSDate?.Type:
                if let v = try! row.get(Expression<NSDate?>(column)) {
                    setValue(v, forKey: attribute)
                }else{
                    setValue(nil, forKey: attribute)
                }

            default: break

            }

        }
    }
    
    internal func buildFromRowUseCodable(row:Row) -> Self{
        
        var dic = [String:Any]()
        for case let (attribute?,column?, value) in recursionProperties() {
            //            let s = "Attribute ：\(attribute) Value：\(value),   " +
            //                    "Mirror: \(Mirror(reflecting:value)),  " +
            //                    "Mirror.subjectType: \(Mirror(reflecting:value).subjectType),    " +
            //                    "Mirror.displayStyle: \(String(describing: Mirror(reflecting:value).displayStyle))"
            //            LogDebug(s)
            //            LogDebug("assign Value-\(value) to \(attribute)-attribute of \(nameOfTable). ")
            
            
            let mir = Mirror(reflecting:value)
            
            switch mir.subjectType {
                
            case _ as String.Type:
                dic[attribute] = row[Expression<String>(column)]
            case _ as String?.Type:
                if let v = row[Expression<String?>(column)] {
                    dic[attribute] = v
                }else{
//                    dic[attribute] = nil
                }
                
                
            case _ as NSNumber.Type:
                
                if self.doubleTypes().contains(attribute) {
                    dic[attribute] = NSNumber(value:try! row.get(Expression<Double>(column)))
                }else{
                    let v = try! row.get(Expression<NSNumber>(column))
                    dic[attribute] = v
                }
                
            case _ as NSNumber?.Type:
                
                if self.doubleTypes().contains(attribute) {
                    if let v = try! row.get(Expression<Double?>(column)) {
                        dic[attribute] = NSNumber(value:v)
                    }
                }else{
                    if let v = try! row.get(Expression<NSNumber?>(column)) {
                        dic[attribute] = v
                    }else{
                        //                    dic[attribute] = nil
                    }
                }
                
            case _ as NSDate.Type:
                dic[attribute] = try! row.get(Expression<NSDate>(column))
            case _ as NSDate?.Type:
                if let v = try! row.get(Expression<NSDate?>(column)) {
                    dic[attribute] = v
                }else{
                    //                    dic[attribute] = nil
                }
                
            default: break
                
            }
            
        }
        
        if (try? JSONSerialization.data(withJSONObject: dic, options: JSONSerialization.WritingOptions.prettyPrinted)) != nil{
//            return try! JSONDecoder().decode(type(of: self), from: jsonData)
        }
        
        return type(of: self).init() 
    }
    
    func recursionPropertiesOnlyColumn() -> [(String?,Any)]{
        
        var properties = [(String?,Any)]()
        var mirror: Mirror? = Mirror(reflecting: self)
        repeat {
            for case let (key?, value) in mirror!.children {
                
                if isSupportTypes(value){
                    if let column = mapper()[key] {
                        properties.append((column, value))
                    }else{
                        properties.append((key, value))
                    }
                }
                
            }
            mirror = mirror?.superclassMirror
        } while mirror != nil
        
        return properties.sorted(by: {
            if $0.0 ==  primaryKeyAttributeName {
                return true
            }
            return $0.0! < $1.0!
        } )
    }
    
    func recursionProperties() -> [(String?,String?,Any)]{
        
        var properties = [(String?,String?,Any)]()
        var mirror: Mirror? = Mirror(reflecting: self)
        repeat {
            for case let (attribute?, value) in mirror!.children {
                
                if noSavedProperties().contains(attribute){
                    continue
                }
                
                if isSupportTypes(value) {
                    if let column = mapper()[attribute] {
                        properties.append((attribute, column, value))
                    }else{
                        properties.append((attribute, attribute, value))
                    }
                }
                
            }
            mirror = mirror?.superclassMirror
        } while mirror != nil
        
        return properties.sorted(by: {
            if $0.0 == primaryKeyAttributeName {
                return true
            }
            return $0.0! < $1.0!
        } )
    }
    
    func propertieColumnMap() -> [String:String]{
        
        var pcMap = [String:String]()
        var mirror: Mirror? = Mirror(reflecting: self)
        repeat {
            for case let (key?, value) in mirror!.children {
                
                if noSavedProperties().contains(key)  {
                    continue
                }
                
                if isSupportTypes(value){
                    if let column = mapper()[key] {
                        pcMap[key] = column
                    }else{
                        pcMap[key] = key
                    }
                }
                
            }
            mirror = mirror?.superclassMirror
        } while mirror != nil
        
        
        return pcMap
    }
    
    

    internal var primaryKeyAttributeName:String{
        return "id"
    }
    
    internal func noSavedProperties() -> [String]{
        if type(of: self).isSaveDefaulttimestamp{
            return transientTypes()
        }else{
            return transientTypes() + [type(of: self).CREATE_AT_KEY,type(of: self).UPDATE_AT_KEY]
        }
    }
}

