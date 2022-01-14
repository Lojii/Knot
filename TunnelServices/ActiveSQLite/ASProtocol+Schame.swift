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
            try getDB().run(getTable().create(ifNotExists: true) { t in
                
                
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
            
            Log.i("Create  Table \(nameOfTable) success")
        }catch let e{
            Log.e("Create  Table \(nameOfTable)failure：\(e.localizedDescription)")
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
            try getDB().run(getTable().drop(ifExists: true))
            Log.i("Delete  Table \(nameOfTable) success")
            
        }catch{
            Log.e("Delete  Table \(nameOfTable)failure：\(error.localizedDescription)")
            throw error
        }
        
    }
    
    //MARK: - Alter Table
    //MARK: - Rename Table
    static func renameTable(oldName:String, newName:String)throws{
        do{
            try getDB().run(Table(oldName).rename(Table(newName)))
            Log.i("alter name of table from \(oldName) to \(newName) success")
            
        }catch{
            Log.e("alter name of table from \(oldName) to \(newName) failure：\(error.localizedDescription)")
            throw error
        }
        
    }
    
    //MARK: - Add Column
    static func addColumn(_ columnNames:[String])throws {
        do{
            try getDB().savepoint("savepointname_\(nameOfTable)_addColumn_\(NSDate().timeIntervalSince1970 * 1000)", block: {
                //            try self.db.transaction {
                let t = getTable()
                for columnName in columnNames {
                    try self.getDB().run(self.init().addColumnReturnSQL(t: t, columnName: columnName)!)
                }
                
                //            }
            })
            Log.i("Add \(columnNames) columns to \(nameOfTable) table success")
            
        }catch{
            Log.e("Add \(columnNames) columns to \(nameOfTable) table failure")
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
            try getDB().run(getTable().createIndexBrage(columns))
            Log.i("Create \(columns) indexs on \(nameOfTable) table success")
            
            
        }catch{
            Log.e("Create \(columns) indexs on \(nameOfTable) table failure")
            throw error
        }
    }
    
    static func createIndex(_ columns: [Expressible], unique: Bool = false, ifNotExists: Bool = false)throws {
        do{
            
            try getDB().run(getTable().createIndexBrage(columns, unique: unique, ifNotExists: ifNotExists))
            Log.i("Create \(columns) indexs on \(nameOfTable) table success")
            
        }catch{
            Log.e("Create \(columns) indexs on \(nameOfTable) table failure")
            throw error
        }
    }
    
    // MARK: - DROP INDEX
    static func dropIndex(_ columns: Expressible...) -> Bool {
        do{
            try getDB().run(getTable().dropIndexBrage(columns))
            Log.i("Drop \(columns) indexs from \(nameOfTable) table success")
            return true

        }catch{
            Log.e("Drop \(columns) indexs from \(nameOfTable) table failure")
            return false
        }
    }
    
    static func dropIndex(_ columns: [Expressible], ifExists: Bool = false) -> Bool {
        do{
        
            try getDB().run(getTable().dropIndexBrage(columns, ifExists: ifExists))
            Log.i("Drop \(columns) indexs from \(nameOfTable) table success")
            return true
        
        }catch{
            Log.e("Drop \(columns) indexs from \(nameOfTable) table failure")
            return false
        }
    }
}


