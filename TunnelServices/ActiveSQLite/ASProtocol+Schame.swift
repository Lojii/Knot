//
//  ASProtocolSchame.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 08/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite


public protocol CreateColumnsProtocol {
    func createColumns(t:TableBuilder)
}

public extension ASProtocol where Self:ASModel{
    
    internal func createTable()throws{
        //        type(of: self).createTable()
        
        do{
            try db.run(getTable().create(ifNotExists: true) { t in
                
                
                if self is CreateColumnsProtocol {
                    (self as! CreateColumnsProtocol).createColumns(t: t)
                }else{
                    autoCreateColumns(t)
                }
                
                //                let s = recusionProperties(t)
                //                (s["definitions"] as! [Expressible]).count
                //
                //                let create1: Method = class_getClassMethod(self, #selector(ASModel.createTable))
                //                let create2: Method = class_getClassMethod(self, #selector(self.createTable))
                //
                
            })
            
            LogInfo("Create  Table \(nameOfTable) success")
        }catch let e{
            LogError("Create  Table \(nameOfTable)failure：\(e.localizedDescription)")
            throw e
        }
        
    }
    static func createTable()throws{
        try self.init().createTable()
    }
    
    internal  func autoCreateColumns(_ t:TableBuilder){
        for case let (attribute?,column?, value) in self.recursionProperties() {
            
            //check primaryKey
            if attribute == primaryKeyAttributeName {
                t.column(Expression<NSNumber>(column), primaryKey: .autoincrement)
                continue
            }
            
            let mir = Mirror(reflecting:value)
            
            switch mir.subjectType {
                
            case _ as String.Type:
                t.column(Expression<String>(column), defaultValue: "")
            case _ as String?.Type:
                t.column(Expression<String?>(column))
                
                
            case _ as NSNumber.Type:
                
                if doubleTypes().contains(attribute) {
                    t.column(Expression<Double>(column), defaultValue: 0.0)
                }else{
                    
                    if attribute == primaryKeyAttributeName {
                        t.column(Expression<NSNumber>(column), primaryKey: .autoincrement)
                    }else{
                        t.column(Expression<NSNumber>(column), defaultValue: 0)
                    }
                    
                }
                
            case _ as NSNumber?.Type:
                
                if doubleTypes().contains(attribute) {
                    t.column(Expression<Double?>(column))
                }else{
                    t.column(Expression<NSNumber?>(column))
                }
                
            case _ as NSDate.Type:
                t.column(Expression<NSDate>(column), defaultValue: NSDate(timeIntervalSince1970: 0))
            case _ as NSDate?.Type:
                t.column(Expression<NSDate?>(column))
                
            default: break
                
            }
            
        }
    }
    
    static func dropTable()throws{
        do{
            try db.run(getTable().drop(ifExists: true))
            LogInfo("Delete  Table \(nameOfTable) success")
            
        }catch{
            LogError("Delete  Table \(nameOfTable)failure：\(error.localizedDescription)")
            throw error
        }
        
    }
    
    //MARK: - Alter Table
    //MARK: - Rename Table
    static func renameTable(oldName:String, newName:String)throws{
        do{
            try db.run(Table(oldName).rename(Table(newName)))
            LogInfo("alter name of table from \(oldName) to \(newName) success")
            
        }catch{
            LogError("alter name of table from \(oldName) to \(newName) failure：\(error.localizedDescription)")
            throw error
        }
        
    }
    
    //MARK: - Add Column
    static func addColumn(_ columnNames:[String])throws {
        do{
            try db.savepoint("savepointname_\(nameOfTable)_addColumn_\(NSDate().timeIntervalSince1970 * 1000)", block: {
                //            try self.db.transaction {
                let t = getTable()
                for columnName in columnNames {
                    try self.db.run(self.init().addColumnReturnSQL(t: t, columnName: columnName)!)
                }
                
                //            }
            })
            LogInfo("Add \(columnNames) columns to \(nameOfTable) table success")
            
        }catch{
            LogError("Add \(columnNames) columns to \(nameOfTable) table failure")
            throw error
        }
    }
    
    private func addColumnReturnSQL(t:Table,columnName newAttributeName:String)->String?{
        for case let (attribute?,column?, value) in self.recursionProperties() {
            
            if newAttributeName != attribute {
                continue
            }
            
            
            let mir = Mirror(reflecting:value)
            
            switch mir.subjectType {
                
            case _ as String.Type:
                return t.addColumn(Expression<String>(column), defaultValue: "")
            case _ as String?.Type:
                return t.addColumn(Expression<String?>(column))
                
                
            case _ as NSNumber.Type:
                
                if doubleTypes().contains(attribute) {
                    return t.addColumn(Expression<Double>(column), defaultValue: 0.0)
                }else{
                    
                    //                    if key == primaryKeyAttributeName {
                    //                        return t.addColumn(Expression<NSNumber>(key), primaryKey: .autoincrement)
                    //                    }else{
                    return t.addColumn(Expression<NSNumber>(column), defaultValue: 0)
                    //                    }
                    
                }
                
            case _ as NSNumber?.Type:
                
                if doubleTypes().contains(attribute) {
                    return t.addColumn(Expression<Double?>(column))
                }else{
                    return t.addColumn(Expression<NSNumber?>(column))
                }
                
            case _ as NSDate.Type:
                return t.addColumn(Expression<NSDate>(column), defaultValue: NSDate(timeIntervalSince1970: 0))
            case _ as NSDate?.Type:
                return t.addColumn(Expression<NSDate?>(column))
                
            default:
                return nil
            }
            
        }
        return nil
    }
    
    // MARK: - CREATE INDEX
    static func createIndex(_ columns: Expressible...)throws {
        do{
            try db.run(getTable().createIndexBrage(columns))
            LogInfo("Create \(columns) indexs on \(nameOfTable) table success")
            
            
        }catch{
            LogError("Create \(columns) indexs on \(nameOfTable) table failure")
            throw error
        }
    }
    
    static func createIndex(_ columns: [Expressible], unique: Bool = false, ifNotExists: Bool = false)throws {
        do{
            
            try db.run(getTable().createIndexBrage(columns, unique: unique, ifNotExists: ifNotExists))
            LogInfo("Create \(columns) indexs on \(nameOfTable) table success")
            
        }catch{
            LogError("Create \(columns) indexs on \(nameOfTable) table failure")
            throw error
        }
    }
    
    // MARK: - DROP INDEX
    static func dropIndex(_ columns: Expressible...) -> Bool {
        do{
            try db.run(getTable().dropIndexBrage(columns))
            LogInfo("Drop \(columns) indexs from \(nameOfTable) table success")
            return true

        }catch{
            LogError("Drop \(columns) indexs from \(nameOfTable) table failure")
            return false
        }
    }
    
    static func dropIndex(_ columns: [Expressible], ifExists: Bool = false) -> Bool {
        do{
        
            try db.run(getTable().dropIndexBrage(columns, ifExists: ifExists))
            LogInfo("Drop \(columns) indexs from \(nameOfTable) table success")
            return true
        
        }catch{
            LogError("Drop \(columns) indexs from \(nameOfTable) table failure")
            return false
        }
    }
}


