//
//  City2.swift
//  ActiveSQLiteTests
//
//  Created by kai zhou on 19/01/2018.
//  Copyright © 2018 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite
@testable import ActiveSQLite

class City2: ASModel {
    var code:String = ""
    var name:String = ""
    
    
    override class var nameOfTable: String{
        return "City"
    }
    
    override class var dbName:String?{
        return DBName2
    }
    
    override class var PRIMARY_KEY:String{
        return "_id"
    }
    
    override func mapper() -> [String:String]{
        return ["id":"_id"]
    }
    
    override class var isSaveDefaulttimestamp:Bool{
        return true
    }
    
}
