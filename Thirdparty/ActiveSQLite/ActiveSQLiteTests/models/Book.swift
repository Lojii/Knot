//
//  Book.swift
//  ActiveSQLiteTests
//
//  Created by Kevin Zhou on 2020/3/11.
//  Copyright © 2020 hereigns. All rights reserved.
//

import Foundation
import SQLite
@testable import ActiveSQLite

//class Book:ASModel{
//
//
//    var name:String = ""
//    var type:Int!
//
//
//    override var nameOfTable: String{
//        if type  == 1 {
//            return "BookTable1"
//        }else{
//            return "BookTable2"
//        }
//    }
//}

class Book:ASModel{
    
    
    var name:String = ""
    var type:Int!


    override class var nameOfTable: String{
        return "BookTable1"
    }
}

class Book2:Book{
    
    override class var nameOfTable: String{
        return "BookTable2"
    }
}
