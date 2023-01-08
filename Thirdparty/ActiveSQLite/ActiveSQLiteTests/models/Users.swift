//
//  Users.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 09/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite
@testable import ActiveSQLite

class Users:ASModel,CreateColumnsProtocol{
    
    var name:String = "String"
        
    static let name = Expression<String>("name")

    
    
    func createColumns(t: TableBuilder) {
        t.column(Users.id, primaryKey: true)
        t.column(Users.name,defaultValue:"")
        t.column(Expression<NSDate>("created_at"), defaultValue: NSDate(timeIntervalSince1970: 0))
        t.column(Expression<NSDate>("updated_at"), defaultValue: NSDate(timeIntervalSince1970: 0))
    }
    
    override class var isSaveDefaulttimestamp:Bool{
        return true
    }
}
