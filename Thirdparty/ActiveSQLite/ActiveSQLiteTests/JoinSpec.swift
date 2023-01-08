//
//  JoinSpec.swift
//  ActiveSQLite
//
//  Created by Kevin Zhou on 09/06/2017.
//  Copyright © 2017 wumingapie@gmail.com. All rights reserved.
//

import Quick
import Nimble
import SQLite

@testable import ActiveSQLite

class JoinSpec: QuickSpec {
    override func spec() {

        ASConfigration.setDefaultDB(path: getTestDBPath()!, name: DBDefaultName)
        
        describe("generate datas") {
            
            try? Users.dropTable()
            try? Posts.dropTable()
            
            let p = Posts()
            p.user_id = 888
            p.title = "Title999"
            try! p.save()
            
            
            let u = Users()
            u.name = "Peter"
            try! u.save()
            
            let u2 = Users()
            u2.name = "Paul"
            try! u2.save()
            
            for i in 0 ..< 5{
                let p = Posts()
                if i < 2{
                    p.user_id = u.id!
                }else{
                    p.user_id = u2.id!
                }
                p.title = "Title\(i)"
                try! p.save()
            }
            
            
            describe("joinQuery", {
                let users = Table("Users")
                let posts = Table("Posts")
                
//                users.join(posts, on: Posts.user_id == users[Expression<Int64>("id")])
                let query = users.join(posts, on: Posts.user_id == users.namespace(Users.id)).filter(Posts.user_id == u.id!)
                
                
                let db = try! ASConfigration.getDefaultDB()
                
                for result in try! db.prepare(query) {
                   debugPrint("Results of join Query -> \(result)" )
                   
                }
//                SELECT * FROM "Users" INNER JOIN "Posts" ON ("user_id" = "Users"."id")
//                //   Users   Table                             |     Posts    Table 
//                //created_at    id   name    updated_at    |    created_at   id  title    updated_at
//                "1497235117046"	"1"	"Peter"	"1497235117046"	"1497235117055"	"1"	"Title0"	"1497235117055"	"1"
//                "1497235117046"	"1"	"Peter"	"1497235117046"	"1497235117058"	"2"	"Title1"	"1497235117058"	"1"
//                "1497235117051"	"2"	"Paul"	"1497235117051"	"1497235117061"	"3"	"Title2"	"1497235117061"	"2"
//                "1497235117051"	"2"	"Paul"	"1497235117051"	"1497235117064"	"4"	"Title3"	"1497235117064"	"2"
//                "1497235117051"	"2"	"Paul"	"1497235117051"	"1497235117067"	"5"	"Title4"	"1497235117067"	"2"
                
                
//                SELECT * FROM "Users" INNER JOIN "Posts" ON ("user_id" = "Users"."id") where "user_id" = 1
//                //   Users   Table                             |     Posts    Table 
//                //created_at    id   name    updated_at    |    created_at   id  title    updated_at
//                "1497235117046"	"1"	"Peter"	"1497235117046"	"1497235117055"	"1"	"Title0"	"1497235117055"	"1"
//                "1497235117046"	"1"	"Peter"	"1497235117046"	"1497235117058"	"2"	"Title1"	"1497235117058"	"1"
                
            })
        }
    }
}
