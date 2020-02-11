//
//  Utils.swift
//  ActiveSQLite
//
//  Created by kai zhou on 19/01/2018.
//  Copyright © 2018 wumingapie@gmail.com. All rights reserved.
//

import Foundation
import SQLite

//project name
func bundleName() -> String{
    var bundlePath = Bundle.main.bundlePath
    bundlePath = bundlePath.components(separatedBy: "/").last!
    bundlePath = bundlePath.components(separatedBy: "/").first!
    return bundlePath
}

//class name -> AnyClass
func getClass(name:String) ->AnyClass?{
    let type = bundleName() + "." + name
    return NSClassFromString(type)
}

//MARK: - Extension



func recusionProperties(_ obj:Any) -> Dictionary<String,Any> {
    var properties = [String:Any]()
    var mirror: Mirror? = Mirror(reflecting: obj)
    repeat {
        for case let (key?, value) in mirror!.children {
            properties[key] = value
        }
        mirror = mirror?.superclassMirror
    } while mirror != nil
    
    return properties
}

extension Setter{
    func getColumnName() -> String {
        let selfPrpperties = recusionProperties(self)
        for case let (key, v) in selfPrpperties{
            if key == "column" {
                let columnPrpperties = recusionProperties(v)
                for case let (key, v) in columnPrpperties{
                    if key == "template" {
                        return (v as! String).trimmingCharacters(in: CharacterSet(charactersIn:"\""))
                    }
                }
            }
        }
        
        return ""
        //        return (recusionProperties(self)["column"] as! Expression).template
    }
    
    func getValue() -> Any? {
        let selfPrpperties = recusionProperties(self)
        for case let (key, v) in selfPrpperties{
            if key == "value" {
                return v
            }
        }
        
        return nil
        
    }
}

//variable argument  contvert to array argument
extension Table{
    // MARK: - CREATE INDEX
    public func createIndexBrage(_ columns: [Expressible]) -> String {
        typealias Function = ((_ columns:[Expressible],_ unique: Bool , _ ifNotExists: Bool ) -> String)
        let createIndexNew = unsafeBitCast(createIndex(_:unique:ifNotExists:), to: Function.self)
        return createIndexNew(columns, false, false)
    }
    
    public func createIndexBrage(_ columns: [Expressible], unique: Bool = false, ifNotExists: Bool = false) -> String {
        typealias Function = ((_ columns:[Expressible],_ unique: Bool , _ ifNotExists: Bool ) -> String)
        let createIndexNew = unsafeBitCast(createIndex(_:unique:ifNotExists:), to: Function.self)
        return createIndexNew(columns, unique, ifNotExists)
    }
    
    // MARK: - DROP INDEX
    public func dropIndexBrage(_ columns: [Expressible]) -> String {
        typealias Function = (_ columns: [Expressible]) -> String
        let dropIndexNew = unsafeBitCast(dropIndex(), to: Function.self)
        return dropIndexNew(columns)
    }
    public func dropIndexBrage(_ columns: [Expressible], ifExists: Bool = false) -> String {
        typealias Function = (_ columns: [Expressible], _ ifExists: Bool ) -> String
        let dropIndexNew = unsafeBitCast(dropIndex(_:ifExists), to: Function.self)
        return dropIndexNew(columns, ifExists)
    }
}
