//
//  ErrorTests.swift
//  ActiveSQLiteTests
//
//  Created by Kevin Zhou on 2020/7/7.
//  Copyright © 2020 hereigns. All rights reserved.
//

import Foundation

import Quick
import Nimble
import SQLite

@testable import ActiveSQLite


/// 测试错误。（db没找到错误）

class ErrorTests: QuickSpec {
    
    
    override func spec() {
        
        //方法体来自MultiDBSpec.swift。区别是注释掉了数据库创建方法。
        
        ASConfigration.setDefaultDB(path: getTestDBPath()!, name: DBDefaultName)
        
        
        let dbPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + "/NotFoundSQLite.db"
        try? FileManager.default.removeItem(atPath: dbPath)
        ASConfigration.setDB(path:dbPath, name: DBName2,isAutoCreate: false)
        
        try? City.dropTable()
        try? City2.dropTable()
        
        describe("Insert cities in db1") {
            
            ActiveSQLite.save({
                
                try City.dropTable()
                
                var cities = [City]()
                for i in 0 ..< 10 {
                    let c = City()
                    c.name = "City name \(i) in DB1"
                    c.code = String(i)
                    cities.append(c)
                }
                
                try City.insertBatch(models: cities)
                
                
                for (index,city) in cities.enumerated(){
                    XCTAssertTrue(city.id!.intValue > 0)
                    XCTAssertEqual(city.name, "City name \(index) in DB1")
                    XCTAssertEqual(city.code, String(index))
                }
                
                
            }, completion: { (error) in
                
//                expect(error).notTo(beNil())
//                expect(error).to(beNil())
                debugPrint("错误：\(String(describing: error))")
            })
           
            
        }
        
        //不在otherDB插入数据
//        describe("Insert cities in db2") {
//            ActiveSQLite.save({
//
//                try City2.dropTable()
//
//                var cities = [City2]()
//                for i in 0 ..< 5 {
//                    let c = City2()
//                    c.name = "City name \(i) in DB2"
//                    c.code = String(i)
//                    cities.append(c)
//                }
//
//                try City2.insertBatch(models: cities)
//
//
//                for (index,city) in cities.enumerated(){
//                    XCTAssertTrue(city.id!.intValue > 0)
//                    XCTAssertEqual(city.name, "City name \(index) in DB2")
//                    XCTAssertEqual(city.code, String(index))
//                }
//
//            }, completion: { (error) in
//
////                expect(error).notTo(beNil())
//
//                debugPrint("错误：\(error)")
//            })
//
//
//        }
        
        describe("Find cities ") {
            
            ActiveSQLite.save({
                
                let cities1 = City.findAll(orderColumn: "id")
                expect(cities1.count).to(equal(10))
                expect(cities1.last?.name).to(equal("City name 9 in DB1"))
                
                
                //不插入数据情况下，测试查找无值。
                let cities2 = City2.findAll(orderColumn: "id")
                expect(cities2.count).to(equal(0))
                
                
            }, completion: { (error) in
                
//                expect(error).notTo(beNil())
                
                debugPrint("错误：\(String(describing: error))")
            })
            
            
            
        }

    }

}


