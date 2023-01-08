//
//  Rule.swift
//  NIOMan
//
//  Created by LiuJie on 2022/4/6.
//

import UIKit
import ActiveSQLite
import SQLite

public enum RuleModel:String {
    case Black = "black"
    case White = "white"
}

public class Rule: ASModel {
    
    public var author: String = ""             // 作者
    public var homepage: String = ""           // 主页
    public var version: String = "1.0.0"       // 版本
    public var create_time: String = ""        // 创建时间
    public var last_time: String = ""          // 最后一次使用时间
    public var name: String = ""               // 名称
    public var model: String = "black"         // 模式：black，white，pac  黑名单模式、白名单模式、自定义pac模式
    public var modelType: RuleModel {
        get {
            if model == "black" {
                return .Black
            }else {
                return .White
            }
        }
        set {
            model = newValue.rawValue
        }
    }
    public var match_host:String = ""        // host匹配列表
    public var match_host_array: [String] {
        get {
            if match_host == "" { return [] }
            return match_host.components(separatedBy: ",")
        }
        set {
            match_host = newValue.joined(separator: ",").replacingOccurrences(of: "\n", with: "")
        }
    }
    public var ignore_suggest:String = "1"  // 忽略建议项
    public var is_default: String = "0" // 是否默认的那个，如果是，则不允许删除和修改
    
    public var pac: String = ""                // 自定义pac文件
    public var rewrite: String = ""            // 重写脚本
    public var note: String = ""               // 备注
    
    public var ignore_host_array: [String] {
        get {
            if let blacklistPath = NIOMan.CertPath()?.appendingPathComponent("blacklist"), var blacklist = try? String(contentsOf: blacklistPath, encoding: .utf8) {
                blacklist = blacklist.replacingOccurrences(of: "\n", with: "")
                return blacklist.components(separatedBy: ",")
            }
            return []
        }
    }
    
    public func ignoreSuggest() -> Bool{ return ignore_suggest == "1" }
    public func setIgnoreSuggest(_ value: Bool){ ignore_suggest = value ? "1" : "0" }
    public func isDefault() -> Bool{ return is_default == "1" }
    public func setIsDefault(_ value: Bool){ is_default = value ? "1" : "0" }
    
    public var jsonConfig: String {
        get {
            var dic = [String: Any]()
            dic["author"] = author
            dic["homepage"] = homepage
            dic["version"] = version
            dic["name"] = name
            dic["model"] = model
            dic["match_host"] = match_host
            dic["ignore_suggest"] = ignoreSuggest()
            dic["note"] = note
            return dic.toJson()
        }
        set {
            let dic = [String: Any].fromJson(newValue)
            if let value = dic["author"] as? String { author = value }
            if let value = dic["homepage"] as? String { homepage = value }
            if let value = dic["version"] as? String { version = value }
            if let value = dic["name"] as? String { name = value }
            if let value = dic["model"] as? String { model = value }
            if let value = dic["match_host"] as? String { match_host = value }
            if let value = dic["note"] as? String { note = value }
            if let value = dic["ignore_suggest"] as? Bool { setIgnoreSuggest(value) }
        }
    }
    
    public func pacJS(proxy:String) -> String {
        var js = """
        function FindProxyForURL(url, host) {
            return "PROXY \(proxy)";
        }
        """
        let jsHead = """
        function FindProxyForURL(url, host) {
            if (
        """
        var ifStr = ""
        var jsEnd = ""
        var hosts = match_host_array
        if modelType == .Black { // 黑名单模式
            for igHost in ignore_host_array {
                hosts.append(igHost)
            }
            jsEnd = """
            ) {
                    return "DIRECT";
                }
                return "PROXY \(proxy)";
            }
            """
        }else{ // 白名单模式
            jsEnd = """
            ) {
                    return "PROXY \(proxy)";
                }
                return "DIRECT";
            }
            """
        }
        for i in 0..<hosts.count {
            let host = hosts[i]
            var partStr = "shExpMatch(host,\"\(host)\")"
            if i >= hosts.count - 1 {
                
            }else{
                partStr = "\(partStr) || "
            }
            ifStr.append(partStr)
        }
        if ifStr != "" {
            js = "\(jsHead)\(ifStr)\(jsEnd)"
        }
        return js
    }
    
    public static func fromConfig(_ config:String = "") -> Rule { // 从json字符串创建
        let rule = Rule()
//        rule.config = config
        return rule
    }
    
    public static func find(id:NSNumber) -> Rule?{
        let r = Rule.findFirst(["id":id])
        return r
    }
    
    public static func setDefaultRule(_ name:String = "Default"){
        let is_default = Expression<String>("is_default")
        let defaultRules = Rule.findAll(is_default == "1")
        if defaultRules.count > 0 {
            return
        }
        let defaultRule = Rule()
        defaultRule.create_time = Date().fullSting
        defaultRule.name = name
        defaultRule.author = "knot"
        defaultRule.modelType = .Black
        defaultRule.setIgnoreSuggest(true)
        defaultRule.setIsDefault(true)
        try? defaultRule.save()
//        print("默认规则创建成功！")
        let tmp = Rule.findAll(is_default == "1")
        if let dr = tmp.first {
            let gud = UserDefaults(suiteName: GROUPNAME)
            gud?.set("\(dr.id!.intValue)", forKey: CURRENTRULEID)
            gud?.synchronize()
        }
    }
    
    public static func currentRule() -> Rule{
        if let rid = UserDefaults(suiteName: GROUPNAME)?.string(forKey: CURRENTRULEID),let iid = NumberFormatter().number(from: rid){
            ASConfigration.setDefaultDB(path: NIOMan.DBPath(), name: DBDefaultName )
            if let cr = Rule.find(id: iid) {
                return cr
            }
        }
        let defaultRule = Rule()
        defaultRule.create_time = Date().fullSting
        defaultRule.name = "Default"
        defaultRule.author = "knot"
        defaultRule.modelType = .Black
        defaultRule.setIgnoreSuggest(true)
        return defaultRule
    }
    
}
