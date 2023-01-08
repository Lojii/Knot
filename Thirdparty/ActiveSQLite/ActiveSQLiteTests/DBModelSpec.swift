//
//  DBModelSpec.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 05/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Quick
import Nimble

import SQLite 
@testable import ActiveSQLite

class DBModelSpec: QuickSpec {
    override func spec() {
        describe("TestsDatabase ") {
            
            ASConfigration.logLevel = .debug
            ASConfigration.setDefaultDB(path: getTestDBPath()!, name: DBDefaultName)
            
            let model: ProductM = ProductM()

            describe("create Database ", {
                
                describe("Delete Table ", {
                    try? ProductM.dropTable()
                })
                
                describe("create Table ", {
                    
                    try? ProductM.createTable()
                    
                    
                    describe(" insert", {
                        
                        model.name = "iPhone 7"
                        model.price = 1.2
                        try! model.insert()
                        debugPrint(model)
                    })
                    
                    describe(" Update ", {
                        
                        model.name = "iMac"
                        model.price = 99.99
                        try! model.update()
                        debugPrint(model)
                    })

                    describe(" Update -save", {
                        
                        model.name = "iPad"
                        model.price = 55.99
                        try! model.save()
                        debugPrint(model)

                    })
                    
                    describe(" insert-save", {
                        // insert
                        let m2 = ProductM()
                        m2.name = "iWatch"
                        m2.price = 10000
                        try! m2.save()
                    })
                    
//                    describe("Query-Generic Types", {
//                        
//                        let p2 = ProductM().findAll(ProductM.name == "iWatch", toT:ProductM()).first
//                        ProductM.findAll(ProductM.name == "iWatch")
//                        expect(p2!.price).to(equal(10000))
//                        expect(p2!.name).to(equal("iWatch"))
//                        
//                    })
//                    
//                    describe("Query-Generic Types2", {
//                        
//                        let p2:ProductM = ProductM.findAll(ProductM.name == "iWatch").first!
//                        expect(p2.price).to(equal(10000))
//                        expect(p2.name).to(equal("iWatch"))
//                        
//                    })
//                    
//                    describe("Query-Generic Types3", {
//                        
//                        let p2:ProductM = ProductM.findAll(ProductM.name == "iWatch").first!
//                        expect(p2.price).to(equal(10000))
//                        expect(p2.name).to(equal("iWatch"))
//                        
//                    })
                    
                    describe("Query- use as", {
                        
                        let p = ProductM.findAll(ProductM.name == "iWatch").first!
                        expect(p.price).to(equal(10000))
                        expect(p.name).to(equal("iWatch"))
                        
                        
                        let arr = ProductM.findAll(ProductM.name == "iWatch")
                        let p2 = arr.first!
                        expect(p2.price).to(equal(10000))
                        expect(p2.name).to(equal("iWatch"))
                        
                        
                        
                    })
                    
                    
                    describe("Query- use String", {
                        
                        
                        let p = ProductM.findAll("name",value:"iWatch").first!
                        expect(p.price).to(equal(10000))
                        expect(p.name).to(equal("iWatch"))
                        
                        let p2 = ProductM.findAll(["name":"iWatch", "id":2]).first!
                        expect(p2.price).to(equal(10000))
                        expect(p2.name).to(equal("iWatch"))
                        expect(p2.id).to(equal(2))
                        
                    })
                    
                    describe("Query", {
                        let p = ProductM().where("name",value:"iWatch").where(ProductM.id > 0).run().first!
                        expect(p.price).to(equal(10000))
                        expect(p.id).to(equal(2))
                        
                        
                        // insert 10 rows
                        for i in 0..<10{
                            let m = ProductM()
                            m.name = "Product\(i)"
                            m.price = 1.1
                            m.code = NSNumber(value:10 - i)
                            try! m.save()
                        }
                        
                        describe("Expressible Order", {
                            //Query order 
                            let products = ProductM().where(ProductM.code > 3)
                                .order(ProductM.code)
                                .limit(5)
                                .run()
                            
                            //verify Query
                            var i = 4;
                            for product in products{
                                expect(product.code?.intValue).to(equal(i))
                                i += 1
                            }

                        })
                        describe("String Order", {
                            //Query order asc
                            let pros = ProductM().where(ProductM.code > 3)
                                .orderBy("code")
                                .limit(5)
                                .run()
                            
                            //verify Query
                            var i = 4;
                            for product in pros{
                                expect(product.code?.intValue).to(equal(i))
                                i += 1
                            }

                        })
                        
                        
                    })

                    describe("Delete ", { 
                        
                        try! ProductM().where("name",value:"iWatch").runDelete()
                        expect(ProductM.findAll("name",value:"iWatch").count).to(equal(0))
                    })
//
//                    describe("Query use attributes ", {
//                        
//                        
//                        var v = Vocabulary()
//                        if let vv =  v.find(v.schame.KCUUID == NSNumber(value:4579384579438) && v.schame.question == "question1?").first {
//                            vv.print()
//                        }
//                        
//                    })
                })
                
                
            })
            
            
        }

    }
}
