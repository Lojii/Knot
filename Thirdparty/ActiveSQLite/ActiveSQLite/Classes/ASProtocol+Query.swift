//
//  ASProtocol+Query.swift
//  ActiveSQLite
//
//  Created by kai zhou on 2018/5/29.
//  Copyright © 2018 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite

public extension ASProtocol where Self:ASModel{
    
    
    //MARK: - Find
    //MARK: - FindFirst
    static func findFirst(_ attribute: String, value:Any?)->Self?{
        return findAll(attribute, value: value).first
    }
    
    static func findFirst(_ attributeAndValueDic:Dictionary<String,Any?>)->Self?{
        return findAll(attributeAndValueDic).first
    }
    
    static func findFirst(orderColumn:String,ascending:Bool = true)->Self?{
        return findAll(orderColumn:orderColumn, ascending: ascending).first
    }
    
    static func findFirst(orders:[String:Bool]? = nil)->Self?{
        return findAll(orders:orders).first
    }
    
    static func findFirst(_ attribute: String, value:Any?,_ orderBy:String,ascending:Bool = true)->Self?{
        return findAll([attribute:value], [orderBy:ascending]).first
    }
    
    static func findFirst(_ attributeAndValueDic:Dictionary<String,Any?>?,_ orders:[String:Bool]? = nil)->Self?{
        return findAll(attributeAndValueDic, orders).first
    }
    
    static func findFirst(_ predicate: SQLite.Expression<Bool>,orders:[String:Bool])->Self?
    {
        return findAll(predicate,orders:orders).first
    }
    
    static func findFirst(_ predicate: SQLite.Expression<Bool?>,orders:[String:Bool])->Self?{
        return findAll(predicate,orders:orders).first
    }
    
    static func findFirst(_ predicate: SQLite.Expression<Bool>,orders: [Expressible]? = nil)->Self?
    {
        return findAll(predicate,orders:orders).first
    }
    
    static func findFirst(_ predicate: SQLite.Expression<Bool?>,orders: [Expressible]? = nil)->Self?{
        return findAll(predicate,orders:orders).first
    }
    
    
    //MARK: FindAll
    static func findAll(_ attribute: String, value:Any?)->Array<Self>{
        return findAll([attribute:value])
    }
    
    static func findAll(_ attributeAndValueDic:Dictionary<String,Any?>)->Array<Self>{
        return findAll(attributeAndValueDic, nil)
    }
    
    
    static func findAll(orderColumn:String,ascending:Bool = true)->Array<Self>{
        return findAll(nil, [orderColumn:ascending])
    }
    
    static func findAll(orders:[String:Bool]? = nil)->Array<Self>{
        return findAll(nil, orders)
        
    }
    
//    static func findAll(_ attributeAndValueDic:Dictionary<String,Any?>,orders:[String:Bool])->Array<Self>{
//        return findAll(attributeAndValueDic, orders: orders)
//    }
    
    static func findAll(_ attributeAndValueDic:Dictionary<String,Any?>?,_ orders:[String:Bool]? = nil)->Array<Self>{
        
        
        var results:Array<Self> = Array<Self>()
        var query = getTable()
        
        if attributeAndValueDic != nil {
            if let expression = self.init().buildExpression(attributeAndValueDic!) {
                query = query.where(expression)
            }
        }
        
        if orders != nil {
            query = query.order(self.init().buildExpressiblesForOrder(orders!))
        }
        
        do{
            for row in try getDB().prepare(query) {
                let model = self.init()
                model.buildFromRow(row: row) //TODO:codable
                results.append(model)
            }
        }catch{
            Log.e(error)
        }
        
        
        return results
    }
    
    static func findAll(_ predicate: SQLite.Expression<Bool>,orders:[String:Bool])->Array<Self>{
        
        return findAll(Expression<Bool?>(predicate),orders:self.init().buildExpressiblesForOrder(orders))
        
    }
    
    static func findAll(_ predicate: SQLite.Expression<Bool?>,orders:[String:Bool])->Array<Self>{
        
        return findAll(predicate,orders:self.init().buildExpressiblesForOrder(orders))
        
    }
    
    static func findAll(_ predicate: SQLite.Expression<Bool>,order: Expressible)->Array<Self>{
        
        return findAll(Expression<Bool?>(predicate),orders:[order])
    }
    
    static func findAll(_ predicate: SQLite.Expression<Bool>,orders: [Expressible])->Array<Self>{
        
        return findAll(Expression<Bool?>(predicate),orders:orders)
    }
    
    
    static func findAll(_ predicate: SQLite.Expression<Bool>,orders: [Expressible]? = nil)->Array<Self>{
        
        return findAll(Expression<Bool?>(predicate),orders:orders)
    }
    
    
    static func findAll(order: Expressible)->Array<Self>{
        
        return findAll(orders:[order])
    }
    
    static func findAll(_ predicate: SQLite.Expression<Bool?>? = nil,orders: [Expressible]? = nil)->Array<Self>{
        
        var results:Array<Self> = Array<Self>()
        var query = getTable()
        if predicate != nil {
            query = query.where(predicate!)
        }
        
        if orders != nil && orders!.count > 0 {
            query = query.order(orders!)
        }else{
            if isSaveDefaulttimestamp {
                query = query.order(created_at.desc)
            }
        }
        
        
        do{
            for row in try getDB().prepare(query) {
                
                let model = self.init()
                model.buildFromRow(row: row) //TODO:Codable
                
                results.append(model)
            }
        }catch{
            Log.e("Find all for \(nameOfTable) failure: \(error)")
        }
        
        
        return results
    }
    
    //MARK: - Query
    var query:QueryType?{ //TODO:Codable
        set{
            _query = newValue
        }
        get{
            if _query == nil {
                _query =  getTable()
            }
            return _query
//            return nil
        }
    }
    
    
    func join(_ table: QueryType, on condition: Expression<Bool>) -> Self {
        query = query?.join(table, on: condition)
        return self
    }
    
    func join(_ table: QueryType, on condition: Expression<Bool?>) -> Self {
        query = query?.join(table, on: condition)
        return self
    }
    
    func join(_ type: JoinType, _ table: QueryType, on condition: Expression<Bool>) -> Self {
        query = query?.join(type, table, on: condition)
        return self
    }
    
    
    func join(_ type: JoinType, _ table: QueryType, on condition: Expression<Bool?>) -> Self {
        query = query?.join(type, table, on: condition)
        return self
    }
    
    
    func `where`(_ attribute: String, value:Any?)->Self{
        
        if let expression = buildExpression(attribute, value: value) {
            return self.where(expression)
        }
        return self
    }
    
    func `where`(_ attributeAndValueDic:Dictionary<String,Any?>)->Self{
        
        if let expression = buildExpression(attributeAndValueDic) {
            return self.where(expression)
        }
        return self
    }
    
    func `where`(_ predicate: SQLite.Expression<Bool>)->Self{
        query = query?.where(predicate)
        return self
    }
    
    func `where`(_ predicate: SQLite.Expression<Bool?>)->Self{
        query = query?.where(predicate)
        return self
    }
    
    func group(_ by: Expressible...) -> Self {
        query = query?.group(by)
        return self
    }
    
    func group(_ by: [Expressible]) -> Self {
        query = query?.group(by)
        return self
    }
    
    func group(_ by: Expressible, having: Expression<Bool>) -> Self {
        query = query?.group(by, having: having)
        return self
    }
    func group(_ by: Expressible, having: Expression<Bool?>) -> Self {
        query = query?.group(by, having: having)
        return self
    }
    
    func group(_ by: [Expressible], having: Expression<Bool>) -> Self {
        query = query?.group(by, having: having)
        return self
    }
    
    func group(_ by: [Expressible], having: Expression<Bool?>) -> Self {
        query = query?.group(by, having: having)
        return self
    }
    
    func orderBy(_ sorted:String, asc:Bool = true)->Self{
        query = query?.order(buildExpressiblesForOrder([sorted:asc]))
        return self
    }
    
    func orderBy(_ sorted:[String:Bool])->Self{
        query = query?.order(buildExpressiblesForOrder(sorted))
        return self
    }
    
    func order(_ by: Expressible...) -> Self {
        query = query?.order(by)
        return self
    }
    
    func order(_ by: [Expressible]) -> Self {
        query = query?.order(by)
        return self
    }
    
    func limit(_ length: Int?) -> Self {
        query = query?.limit(length)
        return self
    }
    
    func limit(_ length: Int, offset: Int) -> Self {
        query = query?.limit(length, offset: offset)
        return self
    }
    
    func run()->Array<Self>{
        
        var results:Array<Self> = Array<Self>()
        do{
            for row in try type(of: self).getDB().prepare(query!) {
                
                let model = type(of: self).init()
                model.buildFromRow(row: row) //TODO:Codable
                
                results.append(model)
            }
        }catch{
            Log.e("Execute run() from \(nameOfTable) failure。\(error)")
        }
        
        
        query = nil
        
        Log.i("Execute Query run() function from \(nameOfTable)  success")
        
        return results
        
    }
    
    //MARK: delete
    //MARK: - Delete
    func runDelete()throws{
        
        do {
            if try type(of: self).getDB().run(query!.delete()) > 0 {
                Log.i("Delete rows of \(nameOfTable) success")
                
            } else {
                Log.w("Delete rows of \(nameOfTable) failure。")
                
            }
        } catch {
            Log.e("Delete rows of \(nameOfTable) failure。")
            throw error
        }
    }
    
    func delete() throws{
        guard let id = id else {
            return
        }
        
        let query = getTable().where(type(of: self).id == id)
        do {
            if try getDB().run(query.delete()) > 0 {
                Log.i("Delete  \(nameOfTable)，id:\(id)  success")
                
            } else {
                Log.w("Delete \(nameOfTable) failure，haven't found id:\(id) 。")
                
            }
        } catch {
            Log.e("Delete failure: \(error)")
            throw error
        }
    }
    
    static func deleteBatch(_ models:[Self]) throws{
        
        do{
            
            try getDB().savepoint("savepointname_\(nameOfTable)_deleteBatch\(NSDate().timeIntervalSince1970 * 1000)", block: {
                
                var ids = Array<NSNumber>()
                for model in models{
                    if model.id == nil {
                        continue
                    }
                    ids.append(model.id!)
                }
                
                let query = getTable().where(ids.contains(id))
                
                try getDB().run(query.delete())
                
                Log.i("Delete batch rows of \(nameOfTable) success")
            })
        }catch{
            Log.e("Delete batch rows of \(nameOfTable) failure: \(error)")
            throw error
        }
    }
    
    static func deleteAll() throws{
        do{
            try getDB().run(getTable().delete())
            Log.i("Delete all rows of \(nameOfTable) success")
            
        }catch{
            Log.e("Delete all rows of \(nameOfTable) failure: \(error)")
            throw error
        }
    }
}
