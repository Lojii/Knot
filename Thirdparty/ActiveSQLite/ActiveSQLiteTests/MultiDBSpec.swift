//
//  MultiDBSpec.swift
//  ActiveSQLiteTests
//
//  Created by kai zhou on 19/01/2018.
//  Copyright © 2018 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import Quick
import Nimble
import SQLite

@testable import ActiveSQLite

class MultiDBSpec: QuickSpec {
    override func spec() {
        
        ASConfigration.setDefaultDB(path: getTestDBPath()!, name: DBDefaultName)
        ASConfigration.setDB(path: getDB2Path(), name: DBName2)

        
        describe("Insert cities in db1") {
            
            try? City.dropTable()
            
            var cities = [City]()
            for i in 0 ..< 10 {
                let c = City()
                c.name = "City name \(i) in DB1"
                c.code = String(i)
                cities.append(c)
            }
            
            try! City.insertBatch(models: cities)
            

            for (index,city) in cities.enumerated(){
                XCTAssertTrue(city.id!.intValue > 0)
                XCTAssertEqual(city.name, "City name \(index) in DB1")
                XCTAssertEqual(city.code, String(index))
            }
            
        }
        
        describe("Insert cities in db2") {
            
            try? City2.dropTable()
            
            var cities = [City2]()
            for i in 0 ..< 5 {
                let c = City2()
                c.name = "City name \(i) in DB2"
                c.code = String(i)
                cities.append(c)
            }
            
            try! City2.insertBatch(models: cities)
            
            
            for (index,city) in cities.enumerated(){
                XCTAssertTrue(city.id!.intValue > 0)
                XCTAssertEqual(city.name, "City name \(index) in DB2")
                XCTAssertEqual(city.code, String(index))
            }
            
        }

        describe("Find cities ") {
            
            let cities1 = City.findAll(orderColumn: "id")
            expect(cities1.count).to(equal(10))
            expect(cities1.last?.name).to(equal("City name 9 in DB1"))

            
            let cities2 = City2.findAll(orderColumn: "id")
            expect(cities2.count).to(equal(5))
            expect(cities2.first?.name).to(equal("City name 0 in DB2"))
            
            
            
        }
        
    }
}
