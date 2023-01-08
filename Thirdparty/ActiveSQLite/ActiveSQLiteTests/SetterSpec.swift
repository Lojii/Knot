//
//  SetterSpec.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 05/07/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Quick
import Nimble
import SQLite

@testable import ActiveSQLite

class SetterSpec: QuickSpec {
    override func spec() {
        describe("1--- update one by id") {
            
            ASConfigration.setDefaultDB(path: getTestDBPath()!, name: DBDefaultName)
            
            try? ProductM.dropTable()
            let p = ProductM()
            
            describe("save one product") {
                ActiveSQLite.save({
                    
                    p.name = "House"
                    p.price = 9999.99
                    try p.save()
                    
                    
                }, completion: { (error) in
                    
                    expect(error).to(beNil())
                    
                    //                let p = ProductM.findFirst("id", value: 1)!
                    expect(p.name).to(equal("House"))
                })

            }
            
            describe("update by attribute"){
                p.name = "House2"
                try! p.update()
                expect(p.name).to(equal("House2"))
            }
            
            describe("update by setter") {
                try! p.update(ProductM.name <- "apartment",ProductM.price <- 77.77)
                expect(p.name).to(equal("apartment"))
                expect(p.price.doubleValue).to(equal(77.77))
                
            }
        }
        
        describe("2--- batch  update ") {
            
            //save some products
            try? ProductM.dropTable()
            
            var products = [ProductM]()
            for i in 0 ..< 7 {
                let p = ProductM()
                p.name = "iPhone-\(i)"
                p.price = NSNumber(value:i)
                products.append(p)
            }
            
            try! ProductM.insertBatch(models: products)
            
            
            
            describe("update by attribute") {
                
                for i in 0 ..< 7 {
                    let p = products[i]
                    p.desc = "desc-\(i)"
                    p.price = NSNumber(value:i*2)
                }
                
                try! ProductM.updateBatch(models: products)
                
                for i in 0 ..< 7 {
                    let p = products[i]
                    expect(p.desc).to(equal("desc-\(i)"))
                    expect(p.price.doubleValue).to(equal(Double(i*2)))
                }
            }
            
            describe("update by String or Dictionary") {
                
                ActiveSQLite.save({
                    
                    //TODO
                    for i in 3 ..< 7 {
                        try ProductM.update(["desc": "说明\(i)","price":NSNumber(value:i*3)], where: ["id": NSNumber(value:i + 1)])
                    }
                    
                }, completion: { (error) in
                    
                    expect(error).to(beNil())
                    
                    let ps = ProductM.findAll(ProductM.id > NSNumber(value:3), orders: [ProductM.id.asc])
                    
                    for i in 0 ..< 4 {
                        let p = ps[i]
                        expect(p.desc).to(equal("说明\(i+3)"))
                        expect(p.price.doubleValue).to(equal(Double((i+3)*3)))
                    }
                })
                
            }
            
            describe("update by setter") {
                
                ActiveSQLite.save({
                    
                    for i in 0 ..< 7 {
                        try ProductM.update([ProductM.desc <- "介绍\(i)",ProductM.price <- Double(i)], where: ProductM.id == NSNumber(value:i + 1))
                    }
                    
                }, completion: { (error) in
                    
                    expect(error).to(beNil())

                    let ps = ProductM.findAll(ProductM.id > NSNumber(value:0), orders: [ProductM.id.asc])
                    
                    for i in 0 ..< 7 {
                        let p = ps[i]
                        expect(p.desc).to(equal("介绍\(i)"))
                        expect(p.price.doubleValue).to(equal(Double(i)))
                    }
                })

            }


        }
        
        
    }
}
