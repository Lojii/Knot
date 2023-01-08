//
//  TranscationSpec.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 04/07/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Quick
import Nimble

@testable import ActiveSQLite

class TranscationSpec: QuickSpec {
    override func spec() {
        describe("Transcation Tests") {
            ASConfigration.setDefaultDB(path: getTestDBPath()!, name: DBDefaultName)
            
            try? ProductM.dropTable()
            try? Users.dropTable()
            
            ActiveSQLite.save({ 
                

//                let p = ProductM()
//                p.name = "House"
//                p.price = 9999.99
//                try p.save()
                
                
                var products = [ProductM]()
                for i in 0 ..< 3 {
                    let p = ProductM()
                    p.name = "iPhone-\(i)"
                    p.price = NSNumber(value:i)
                    products.append(p)
                }
                
                try ProductM.insertBatch(models: products)
                

                
                let u = Users()
                u.name = "Kevin"
                try u.save()
                
                
                
            }, completion: { (error) in
                
                if error != nil {
                    debugPrint("transtion fails \(String(describing: error))")
                }else{
                    debugPrint("transtion success")
                }

            })
            
        }
    }
}
