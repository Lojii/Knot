//
//  AlterSpec.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 13/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Quick
import Nimble

@testable import ActiveSQLite

class AlterSpec: QuickSpec {
    override func spec() {
        
        describe("Alter Table ") {
            
//
            
//            let db = ASConnection.sharedConnection.db
//            if db.userVersion == 0 {
//                ActiveSQLite.saveAsync({
//                    try Product.renameTable(oldName:"oldTableName",newName:"newTableName")
//                    try Product.addColumn(["newColumn"])
//                    
//                }, completion: { (error) in
//                    
//                    db.userVersion = 1
//                })
//                
//            }
            
            
            debugPrint("Alter Table Tests")
            
            /* 

            //1.db Version
            //.........

            
            //2.Alter  Table 
            expect(ProductM.addColumn(["type"])).to(equal(true))
            
            //3.Tests
            let product = ProductM.findFirst("id", value: 1)!
            XCTAssertNil(product.type)
            
            product.type = 3
            product.save()
            
            let p = ProductM.findFirst("type",value: 3)!
            XCTAssertTrue(p.id == 1)
 
             */

        }
        
//        let db = ProductM().db!
//
//        if db.userVersion == 0 {
//            db.userVersion = 1
//        }
//        if db.userVersion == 1 {
//            // handle second migration
//            db.userVersion = 2
//        }
    }
}
