//
//  MultiTableNameSpec.swift
//  ActiveSQLiteTests
//
//  Created by Kevin Zhou on 2020/3/11.
//  Copyright © 2020 hereigns. All rights reserved.
//

import Quick
import Nimble
import SQLite

@testable import ActiveSQLite

class MultiTableNameSpec: QuickSpec {
    override func spec() {
        describe("insert") {
            
            ASConfigration.setDefaultDB(path: getTestDBPath()!, name: DBDefaultName)
            
            let db = try! ASConfigration.getDefaultDB()
            try? db.run(Table("BookTable1").drop(ifExists: true))
            try? db.run(Table("BookTable2").drop(ifExists: true))
            
           
            for i in 1 ..< 10 {
                
                var b:Book!
                if i % 2 == 0 {
                    b = Book()
                }else{
                    b = Book2()
                }
                
                b.name = "name \(i)"
                b.type = i % 2
                try? b.save()
            }
            
            describe("Look up") {
                let books = Book.findAll(orderColumn: "id")

                debugPrint(books)
                let book2s = Book2.findAll(orderColumn: "id")
                debugPrint(book2s)
//                           expect(cities1.count).to(equal(10))
//                           expect(cities1.last?.name).to(equal("City name 9 in DB1"))
//
//
//                           let cities2 = City2.findAll(orderColumn: "id")
//                           expect(cities2.count).to(equal(5))
//                           expect(cities2.first?.name).to(equal("City name 0 in DB2"))
            }
        }
    }
}
