//
//  SearchOption.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/26.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

enum SearchKey: String {
    case tastID = "tastID"
    case remoteAddress = "remoteAddress"
    case localAddress = "localAddress"
    case host = "host"
    case schemes = "schemes"
    // req head
    case reqLine = "reqLine"
    case methods = "methods"
    case uri = "uri"
    case suffix = "suffix"  // 后缀名
    
    case reqHttpVersion = "reqHttpVersion"
    case reqType = "reqType"
    case reqEncoding = "reqEncoding"
    case reqHeads = "reqHeads"
    case reqDisposition = "reqDisposition"
    case target = "target"
    // rsp head
    case rspHttpVersion = "rspHttpVersion"
    case state = "state"
    case rspMessage = "rspMessage"
    case rspType = "rspType"
    case rspEncoding = "rspEncoding"
    case rspDisposition = "rspDisposition"
    case rspHeads = "rspHeads"
    
    // state
    case sstate = "sstate"
    case note = "note"
    case fileName = "fileName"
    
    func name() -> String {
        switch self {
        case .tastID: return "TaskID"
        case .remoteAddress: return "IP"
        case .localAddress: return "Local IP address".localized
        case .host: return "Host"
        case .schemes: return "Protocol".localized
        case .reqLine: return "Request line".localized
        case .methods: return "Methods".localized
        case .uri: return "Uri"
        case .suffix: return "Type".localized  // 后缀名
        case .reqHttpVersion: return "Version".localized
        case .reqType: return "Original type".localized
        case .reqEncoding: return "Request Coding".localized
        case .reqHeads: return "Request header".localized
        case .reqDisposition: return "Disposition"
        case .target: return "User-Agent".localized
        case .rspHttpVersion: return "Version".localized
        case .state: return "State".localized
        case .rspMessage: return "Message"
        case .rspType: return"Type".localized
        case .rspEncoding: return "Response Coding".localized
        case .rspDisposition: return "Disposition"
        case .rspHeads: return "Response header".localized
        case .sstate: return "sstate"
        case .note: return "note"
        case .fileName: return "File name".localized
        }
    }
}

//enum SearchOrder {
//    case <#case#>
//}

class SearchOption: NSObject {
    var searchWord:String = ""   // 搜索关键词
    var searchMap = [[SearchKey:[String]]]()
    
    func replace(key:SearchKey,values:[String]){
        var find = false
        for index in 0..<searchMap.count{
            var sm = searchMap[index]
            if sm.keys.first == key { // find
                find = true
                if values.count <= 0 {
                    searchMap.remove(at: index)
                    return
                }
                sm[key] = values
                searchMap[index] = sm
                return
            }
        }
        if !find,values.count > 0 {
            searchMap.append([key:values])
        }
    }
    
    func addMap(key:SearchKey,values:[String]){
        for index in 0..<searchMap.count{
            var sm = searchMap[index]
            if sm.keys.first == key { // find
                var vs = sm.values.first ?? [String]()
                for v in values { // add
                    if !vs.contains(v) { vs.append(v) }
                }
                sm[key] = vs
                searchMap[index] = sm
                return
            }
        }
        searchMap.append([key:values])
    }
    
    func delete(key:SearchKey,values:[String]){
        for index in 0..<searchMap.count {
            var sm = searchMap[index]
            if sm.keys.first == key { // find
                guard var vs = sm.values.first else { return}
                for v in values { // add
                    vs.removeAll { (str) -> Bool in
                        return v == str
                    }
                }
                sm[key] = vs
                if vs.count <= 0 {
                    searchMap.remove(at: index)
                }else{
                    searchMap[index] = sm
                }
                return
            }
        }
    }
    
    func removeAll(){
        searchMap.removeAll()
    }
    
    func contains(key:SearchKey,value:String) -> Bool {
        let values = getValues(key: key)
        return values.contains(value)
    }
    
    func getValues(key:SearchKey?) -> [String]{
        if key == nil { return [] }
        for sm in searchMap {
            if sm.keys.first == key {
                return sm.values.first ?? []
            }
        }
        return []
    }
    
    func getACopy() -> SearchOption {
        let so = SearchOption()
        so.searchWord = searchWord
        for sm in searchMap {
            so.searchMap.append(sm)
        }
        return so
    }
}

/*
 FocusOption   [type:[key,key,key]]
 SearchOption   type:[key,key,key]
 FiterOption
 */
