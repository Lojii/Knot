//
//  ASProtocolInsert&Update.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 08/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite

public extension ASProtocol where Self:ASModel{
    
    //MARK: - Insert
    //can't insert reduplicate ids
    func insert()throws {
        
        do {
            try createTable()
            
            var settersInsert = buildSetters(skips: [type(of: self).PRIMARY_KEY, type(of: self).CREATE_AT_KEY, type(of: self).UPDATE_AT_KEY])
            
            
            let timeinterval = NSNumber(value:NSDate().timeIntervalSince1970 * 1000)
            
            if type(of: self).isSaveDefaulttimestamp {
                
                if self.created_at != nil && self.created_at.int64Value > 0 {
                    settersInsert.append(type(of: self).created_at <- self.created_at)
                }else{
                    settersInsert.append(type(of: self).created_at <- timeinterval)
                }
                
                if self.updated_at != nil && self.updated_at.int64Value > 0 {
                    settersInsert.append(type(of: self).updated_at <- self.updated_at)
                }else{
                    settersInsert.append(type(of: self).updated_at <- timeinterval)
                }
            }
            
            if id != nil {
                settersInsert.append(type(of: self).id <- id!)
            }
            
            let rowid = try getDB().run(getTable().insert(settersInsert))
            id = NSNumber(value:rowid)
            
            if type(of: self).isSaveDefaulttimestamp {
                created_at = timeinterval
                updated_at = timeinterval
            }
            
            Log.d("Insert row of \(rowid) into \(nameOfTable) table success ")
        }catch{
            Log.e("Insert row into \(nameOfTable) table failure: \(error)")
            throw error
        }
        
    }
    
    static func insertBatch(models:[Self])throws{
        
        
        //id，created_at,updated_at
        var autoInsertValues = [(NSNumber,NSNumber,NSNumber)]()
        do{
            
            try createTable()
            
            //            try db.transaction {
            try getDB().savepoint("savepointname_\(nameOfTable)_insertbatch_\(NSDate().timeIntervalSince1970 * 1000)", block: {
                for model in models{
                    
                    let timeinterval = NSNumber(value:Int64(NSDate().timeIntervalSince1970 * 1000))
                    
                    var settersInsert = model.buildSetters(skips: [PRIMARY_KEY, CREATE_AT_KEY, UPDATE_AT_KEY])
                    
                    if isSaveDefaulttimestamp {
                        if model.created_at != nil && model.created_at.int64Value > 0 {
                            settersInsert.append(created_at <- model.created_at)
                        }else{
                            settersInsert.append(created_at <- timeinterval)
                        }
                        
                        if model.updated_at != nil && model.updated_at.int64Value > 0 {
                            settersInsert.append(updated_at <- model.updated_at)
                        }else{
                            settersInsert.append(updated_at <- timeinterval)
                        }
                    }
                    
                    if model.id != nil {
                        settersInsert.append(Expression<NSNumber>(PRIMARY_KEY) <- model.id!)
                    }
                    
                    let rowid = try self.getDB().run(getTable().insert(settersInsert))
                    let id = NSNumber(value:rowid)
                    
                    autoInsertValues.append((id,timeinterval,timeinterval))

                }
                
                for i in 0 ..< models.count {
                    models[i].id = autoInsertValues[i].0
                    if isSaveDefaulttimestamp {
                        models[i].created_at = autoInsertValues[i].1
                        models[i].updated_at = autoInsertValues[i].2
                    }
                    
                }
                //            }
            })
            
            Log.i("Batch insert rows(\(models)) into \(nameOfTable) table success")
            
        }catch{
            Log.e("Batch insert rows into \(nameOfTable) table failure:\(error)")
            throw error
            
        }
        
    }
    
    //MARK: - Update
    //MARK: - Update one By id
    func update() throws {
        guard id != nil else {
            Log.e(" Update \(nameOfTable) table failure: id must not be nil.")
            return
        }
        
        do {
            
            let timeinterval = NSNumber(value:NSDate().timeIntervalSince1970 * 1000)
            
            var settersUpdate = buildSetters(skips: [type(of: self).PRIMARY_KEY, type(of: self).UPDATE_AT_KEY])
            if type(of: self).isSaveDefaulttimestamp {
                settersUpdate.append(type(of: self).updated_at <- timeinterval)
            }
            
            
            let table = getTable().where(type(of: self).id == id!)
            let rowid = try getDB().run(table.update(settersUpdate))
            
            if rowid > 0 {
                if type(of: self).isSaveDefaulttimestamp {
                    updated_at = timeinterval
                }
                
                Log.d(" Update row in \(rowid) from \(nameOfTable) Table success ")
            } else {
                Log.w(" Update \(nameOfTable) table failure，can't not found id:\(String(describing: id)) 。")
            }
        } catch {
            Log.e(" Update \(nameOfTable) table failure: \(error)")
            throw error
        }
        
        
    }
    
    func update(_ attribute: String, value:Any?)throws{
        try update([attribute:value])
    }
    
    func update(_ attributeAndValueDic:Dictionary<String,Any?>)throws{
        
        let setterss = buildSetters(attributeAndValueDic)
        try update(setterss)
    }
    
    func update(_ setters: Setter...) throws{
        try update(setters)
    }
    
    func update(_ setters:[Setter])throws{
        guard id != nil else {
            Log.e(" Update \(nameOfTable) table failure: id must not be nil.")
            return
        }
        
        do {
            
            let settersUpdate = (type(of: self)).buildUpdateSetters(setters)
            
            let table = getTable().where(type(of: self).id == id!)
            let rowid = try getDB().run(table.update(settersUpdate))
            
            if rowid > 0 {
                try self.refreshSelf()
                
                Log.d(" Update row in \(rowid) from \(nameOfTable) Table success ")
            } else {
                Log.w(" Update \(nameOfTable) table failure，can't not found id:\(String(describing: id)) 。")
            }
        } catch {
            Log.e(" Update \(nameOfTable) table failure: \(error)")
            throw error
        }
        
    }
    
    //MARK: - Update all
    //MARK: - Update more than one by ids
    static func updateBatch(models:[Self]) throws{
        //updated_at
        var autoUpdateValues = [(NSNumber)]()
        do{
            try getDB().savepoint("savepointname_\(nameOfTable)_updateBatch\(NSDate().timeIntervalSince1970 * 1000)", block: {
                //            try db.transaction {
                for model in models{
                    
                    if model.id == nil {
                        Log.e(" Update \(nameOfTable) table failure: id must not be nil.")
                        continue
                    }
                    
                    var settersUpdate = model.buildSetters(skips: [PRIMARY_KEY, UPDATE_AT_KEY])
                    
                    let timeinterval = NSNumber(value:NSDate().timeIntervalSince1970 * 1000)
                    
                    if isSaveDefaulttimestamp{
                        settersUpdate.append(updated_at <- timeinterval)
                    }
                    
                    
                    let table = model.getTable().where(id == model.id!)
                    try self.getDB().run(table.update(settersUpdate))
                    
                    if isSaveDefaulttimestamp{
                        autoUpdateValues.append((timeinterval))
                    }

                }
                
                if isSaveDefaulttimestamp{
                    for i in 0 ..< models.count {
                        models[i].updated_at = autoUpdateValues[i]
                    }
                }
 
            })
            Log.i("batch Update \(models) on \(nameOfTable) table success")
            
        }catch{
            Log.e("batch Update \(nameOfTable) table failure\(error)")
            throw error
        }
        
    }
    
    static func update(_ attribute: String, value:Any?,`where` wAttribute:String, wValue:Any?)throws{
        try update([attribute:value],where:[wAttribute:wValue])
    }
    
    static func update(_ attributeAndValueDic:Dictionary<String,Any?>,`where` wAttributeAndValueDic:Dictionary<String,Any?>)throws{
        let model = self.init()
        let setterss = model.buildSetters(attributeAndValueDic)
        let expressions = model.buildExpression(wAttributeAndValueDic)!
        try update(setterss, where: expressions)
        
    }
    
    //MARK: - Update more than one by where
    //    static func update(_ setters:Setter...,`where` predicate: SQLite.Expression<Bool>)throws{
    //        try update(setters, where: Expression<Bool?>(predicate))
    //    }
    
    static func update(_ setters:[Setter],`where` predicate: SQLite.Expression<Bool>)throws{
        try update(setters, where: Expression<Bool?>(predicate))
    }
    
    //    static func update(_ setters:Setter...,`where` predicate: SQLite.Expression<Bool?>)throws{
    //        try update(setters, where: predicate)
    //
    //    }
    
    static func update(_ setters:[Setter],`where` predicate: SQLite.Expression<Bool?>)throws{
        do {
            
            
            let table = getTable().where(predicate)
            
            let rowid = try getDB().run(table.update(buildUpdateSetters(setters)))
            
            if rowid > 0 {
                Log.d(" Update row in \(rowid) from \(nameOfTable) Table success ")
            } else {
                Log.w(" Update \(nameOfTable) table failure，can't not found id:\(id) 。")
            }
        } catch {
            Log.e(" Update \(nameOfTable) table failure: \(error)")
            throw error
        }
        
    }
    
    
    
    
    static func update(_ setters:[Setter])throws{
        do {
            
            let rowid = try getDB().run(getTable().update(buildUpdateSetters(setters)))
            
            if rowid > 0 {
                Log.d(" Update row in \(rowid) from \(nameOfTable) Table success ")
            } else {
                Log.w(" Update \(nameOfTable) table failure，can't not found id:\(id) 。")
            }
        } catch {
            Log.e(" Update \(nameOfTable) table failure: \(error)")
            throw error
        }
        
    }
    
    
    
    //MARK: - Save
    //insert if table have't the row，Update if table have the row
    func save() throws{
        do {
            try createTable()
            
            let timeinterval = NSNumber(value:NSDate().timeIntervalSince1970 * 1000)
            
            var created_at_value = timeinterval
            let updated_at_value = timeinterval
            if created_at != nil {
                created_at_value = created_at
            }
            
            var settersInsert = buildSetters(skips: [type(of: self).PRIMARY_KEY, type(of: self).CREATE_AT_KEY, type(of: self).UPDATE_AT_KEY])
            
            if type(of: self).isSaveDefaulttimestamp{
                settersInsert.append(type(of: self).created_at <- created_at_value)
                settersInsert.append(type(of: self).updated_at <- updated_at_value)
            }
            
            if id != nil {
                settersInsert.append(type(of: self).id <- id!)
            }
            
            let rowid = try getDB().run(getTable().insert(or: .replace, settersInsert))
            id = NSNumber(value:rowid)
            if type(of: self).isSaveDefaulttimestamp{
                created_at = created_at_value
                updated_at = updated_at_value
            }
            Log.d("Insert row of \(rowid) into \(nameOfTable) table success ")
        }catch{
            Log.e("Insert into \(nameOfTable) table failure: \(error)")
            throw error
        }
    }
    
    
    
    //MARK: - Common
    internal func refreshSelf() throws{
        var query = getTable().where(type(of: self).id == id!)
        
        if type(of: self).isSaveDefaulttimestamp {
            query = query.order(type(of: self).updated_at.desc)
        }
        
        query = query.limit(1)
        
        
        for row in try getDB().prepare(query) {
            self.buildFromRow(row: row) //TODO:编码
        }
    }
    
    internal func buildSetters(skips:[String] = [PRIMARY_KEY])->[Setter]{
        var setters = [Setter]()
        
        for case let (attribute?,column?, value) in recursionProperties() {
            
            //skip primary key
            if skips.contains(column){
                continue
            }

            let mir = Mirror(reflecting:value)
            
            switch mir.subjectType {
                
            case _ as String.Type:
                setters.append(Expression<String>(column) <- value as! String)
            case _ as String?.Type:
                
                if let v = value as? String {
                    setters.append(Expression<String?>(column) <- v)
                }else{
                    setters.append(Expression<String?>(column) <- nil)
                }
                
                
                
            case _ as NSNumber.Type:
                
                if self.doubleTypes().contains(attribute) {
                    setters.append(Expression<Double>(column) <- value as! Double)
                }else{
                    setters.append(Expression<NSNumber>(column) <- value as! NSNumber)
                }
                
            case _ as NSNumber?.Type:
                
                if self.doubleTypes().contains(attribute) {
                    if let v = value as? Double {
                        setters.append(Expression<Double?>(column) <- v)
                    }else{
                        setters.append(Expression<Double?>(column) <- nil)
                    }
                }else{
                    if let v = value as? NSNumber {
                        setters.append(Expression<NSNumber?>(column) <- v)
                    }else{
                        setters.append(Expression<NSNumber?>(column) <- nil)
                    }
                }
                
            case _ as NSDate.Type:
                setters.append(Expression<NSDate>(column) <- value as! NSDate)
            case _ as NSDate?.Type:
                
                if let v = value as? NSDate {
                    setters.append(Expression<NSDate?>(column) <- v)
                }else{
                    setters.append(Expression<NSDate?>(column) <- nil)
                }
                
            default: break
                
            }
            
//            if let setter = Setter.generate(key: column, type: value, value: value) {
//                setters.append(setter)
//            }
            
        }
        
        return setters
    }
    
    internal func buildSetters(_ attribute:String, value:Any?)->[Setter]{
        return buildSetters([attribute:value])
    }
    
    internal func buildSetters(_ attributeAndValueDic:Dictionary<String,Any?>)->[Setter]{
        
        var setters = Array<Setter>()
        
        for case let (attribute?,column?, v0) in recursionProperties() {
            
            if attributeAndValueDic.keys.contains(attribute) {
                
                let value = attributeAndValueDic[attribute]
                
                let mir = Mirror(reflecting:v0)
                
                switch mir.subjectType {
                    
                case _ as String.Type:
                    setters.append(Expression<String>(column) <- value as! String)
                case _ as String?.Type:
                    
                    if let v = value as? String {
                        setters.append(Expression<String?>(column) <- v)
                    }else{
                        setters.append(Expression<String?>(column) <- nil)
                    }
                    
                    
                    
                case _ as NSNumber.Type:
                    
                    if self.doubleTypes().contains(attribute) {
                        setters.append(Expression<Double>(column) <- value as! Double)
                    }else{
                        setters.append(Expression<NSNumber>(column) <- value as! NSNumber)
                    }
                    
                case _ as NSNumber?.Type:
                    
                    if self.doubleTypes().contains(attribute) {
                        if let v = value as? Double {
                            setters.append(Expression<Double?>(column) <- v)
                        }else{
                            setters.append(Expression<Double?>(column) <- nil)
                        }
                    }else{
                        if let v = value as? NSNumber {
                            setters.append(Expression<NSNumber?>(column) <- v)
                        }else{
                            setters.append(Expression<NSNumber?>(column) <- nil)
                        }
                    }
                    
                case _ as NSDate.Type:
                    setters.append(Expression<NSDate>(column) <- value as! NSDate)
                case _ as NSDate?.Type:
                    
                    if let v = value as? NSDate {
                        setters.append(Expression<NSDate?>(column) <- v)
                    }else{
                        setters.append(Expression<NSDate?>(column) <- nil)
                    }
                    
                default: break
                    
                }
                
//                if let setter = Setter.generate(key: column, type: v0, value: value) {
//                    setters.append(setter)
//                }
                
            }
            
        }
        
        return setters
    }
    
    //if originSetters contains "updated_at", return same setters
    //if originSetters not contains "update_at", return new Setters contains "update_at"
    internal static func buildUpdateSetters(_ originSetters:[Setter])->[Setter]{
        
        //1.Replace double type setter if originSetters contains double type
        var settersUpdate = originSetters.map { (setter) -> Setter in
            
            let column = setter.getColumnName()
            var attribute = column
            for (pro, col) in self.init().propertieColumnMap(){
                if col == column {
                    attribute = pro
                }
            }
            
            //
            if self.init().doubleTypes().contains(attribute) {
                let setterValue = setter.getValue()
                let mir = Mirror(reflecting:setterValue ?? 0.0)
                switch mir.subjectType {
                case _ as NSNumber.Type:
                    return Expression<Double>(column) <- setterValue as! Double
                case _ as NSNumber?.Type:
                    if let v = setterValue as? Double {
                        return Expression<Double?>(column) <- v
                    }else{
                        return Expression<Double?>(column) <- nil
                    }
                default:break
                }
                return setter //the double type that originSetters contains is NSNumber. return origin setter
                //                return Expression<Double?>(column) <- nil
            }else{
                return setter
            }
        }
        
        
        if isSaveDefaulttimestamp {
            // 2.Add "update_at" setter if originSetters not contains "update_at"
            let columnNames:[String] = originSetters.compactMap({ (setter) -> String in
                return setter.getColumnName()
            })
            
            
            var containsUpdate_at = false
            for columnName in columnNames {
                if columnName.contains(UPDATE_AT_KEY) {
                    containsUpdate_at = true
                }
            }
            if !containsUpdate_at {
                settersUpdate.append(updated_at <- NSNumber(value:NSDate().timeIntervalSince1970 * 1000))
            }
        }
        
        
        return settersUpdate
    }
    
}
