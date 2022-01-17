//
//  Rule.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/7.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

public let CurrentRuleDidChange: NSNotification.Name = NSNotification.Name(rawValue: "CurrentRuleDidChange")

public class RuleLine: Equatable {
    
    public var lineType:RuleType = .Other
    var _line: String = ""
    public var line: String {
        get {
            lineWillGet()
            return _line
        }
        set {
            _line = newValue
            lineDidSet()
        }
    }
    
    public static func == (lhs: RuleLine, rhs: RuleLine) -> Bool {
        return lhs.line == rhs.line
    }
    
    func lineDidSet(){
        
    }
    
    func lineWillGet(){
        
    }
}

// 策略
public enum Strategy : String {
    public typealias RawValue = String
    
    case NONE = "-"
    case DIRECT = "DIRECT"  // 直连
    case REJECT = "REJECT"  // 拒绝
    case COPY = "COPY"   // 抓包记录
    case DEFAULT = "DEFAULT"   // 默认
}

// 匹配类型
public enum MatchRule : String  {
    public typealias RawValue = String
    
    case NONE = "-"                         // 域名关键词匹配
    case DOMAINKEYWORD = "DOMAIN-KEYWORD"   // 域名关键词匹配
    case DOMAIN = "DOMAIN"                  // 域名全匹配
    case DOMAINSUFFIX = "DOMAIN-SUFFIX"     // 域名后缀匹配
    case IPCIDR = "IP-CIDR"                 // 远程ip匹配
    case USERAGENT = "USER-AGENT"           // 请求标识匹配
    case URLREGEX = "URL-REGEX"             // URL正则表达式匹配
}

// 行类型
public enum RuleType: String {
    case `Type` = "Type"          // 类型名称 [General]
    case General = "General"    // General 类型  key = value //
    case Rule = "Rule"          // Rule 类型  匹配类型,内容,策略  //注释
    case Host = "Host"          // Host 类型   host = host  //注释
    case Other = "Other"        // 其他类型。空行、单行注释等，已经其他非规则内容
}

public class Rule: ASModel {
    public var subName:String = "new config"
    // [General]
    public lazy var defaulBlacklistRuleItems: [RuleItem] = {
        var blackItems = [RuleItem]()
        if let certDir = MitmService.getCertPath() {
            print("******************* BlackList read !")
            let blackListPath = certDir.appendingPathComponent("DefaultBlackLisk.conf", isDirectory: false)
            if let blackList = try? String(contentsOf: blackListPath, encoding: .utf8) {
                let allLines = blackList.components(separatedBy: "\n")
                for index in 0..<allLines.count {
                    let line = allLines[index]
                    RuleItem.fromLine(line, index, success: { (item) in
                        blackItems.append(item)
                    }, failure: { (errorStr) in
                        print("BlackList index:\(index) error:\(errorStr ?? "unknow")")
                    })
                }
            }
        }
        return blackItems
    }()
    
    var _validRuleItems:[RuleItem]?
    public var validRuleItems: [RuleItem] {
        var items = [RuleItem]()
        for i in 0..<lines.count {
            if let item = lines[i] as? RuleItem {
                item.index = i
                items.append(item)
            }
        }
        return items
    }
    public var numberOfRule: Int {
        return validRuleItems.count
    }
    var _name:String = ""
    public var name: String {
        get { return _name }
        set {
            _name = newValue
            addGeneral("name", _name)
        }
    }
    var _defaultStrategy:Strategy = .COPY  // DEFAULT MODE
    public var defaultStrategy:Strategy {
        get { return _defaultStrategy }
        set {
            _defaultStrategy = newValue
            addGeneral("default-strategy", _defaultStrategy.rawValue)
        }
    }
    var _defaultBlacklistEnable: Bool = true
    public var defaultBlacklistEnable: Bool {
        get { return _defaultBlacklistEnable }
        set {
            _defaultBlacklistEnable = newValue
            addGeneral("default-direct-enable", _defaultBlacklistEnable ? "true" : "false")
        }
    }
    var _createTime: String = Date().fullSting
    public var createTime: String {
        get { return _createTime }
        set {
            _createTime = newValue
            addGeneral("createtime", _createTime)
        }
    }
    var _author:String?
    public var author:String? {
        get { return _author }
        set {
            _author = newValue
            addGeneral("author", _author ?? "")
        }
    }
    var _note:String?
    public var note:String? {
        get { return _note }
        set {
            _note = newValue
            addGeneral("note", _note ?? "")
        }
    }
    
    public var lines = [RuleLine]()
    /*
     [General]
     name = 副本  // 名称
     default-strategy = DIRECT / COPY // 默认策略： 直通或者记录
     default-direct-enable = true  // 启用默认忽略黑名单
     createtime = 2019-06-10 14:46
     author = lojii
     note = 备注信息
     */
    public var ruleItems = [RuleItem]()
    /*
     [Rule]
     DOMAIN,ad.api.3g.youku.com,DEFAULT
     DOMAIN-KEYWORD,ad,DEFAULT
     DOMAIN-SUFFIX,hz.youku.com,DEFAULT
     IP-CIDR,stat.youku.com,DEFAULT
     USER-AGENT,e.stat.ykimg.com,DEFAULT
     URL-REGEX,p-log.ykimg.com,DEFAULT
     */
    public var hosts = [HostItem]()
    /*
     [Host]
     *.pcbeta.com = 218.93.127.136
     cdn.pcbeta.attachment.inimc.com = pcbeta.com
     cdn.pcbeta.static.inimc.com = pcbeta.com
     cdn.pcbeta.css.inimc.com = pcbeta.com
     */
    var _config:String = ""
    public var config: String {
        get {
            // 生成规则配置
            _config = ""
            for line in lines {
                _config.append(line.line)
                _config.append("\n")
            }
            return _config
        }
        set {
            
            _config = newValue
            // 解析规则配置
            configParse()
            NotificationCenter.default.post(name: CurrentRuleDidChange, object: "config")
        }
    }
    
    public static func defaultRule() -> Rule {
        let rule = Rule()
        rule.name = "Knot(Default)"
        rule.defaultStrategy = .DIRECT
        rule.defaultBlacklistEnable = true
        rule.author = "Knot"
        rule.createTime = Date().fullSting
        _ = rule.config
        return rule
    }
    
    public static func fromConfig(_ config:String = "") -> Rule {
        let rule = Rule()
        rule.config = config
        return rule
    }
    
    public func addGeneral(_ key:String, _ value:String){
        let item = GeneralItem()
        item.key = key
        item.value = value
        add(.General, item)
    }
    
    @discardableResult
    public func add(_ type:RuleType, _ item: RuleLine) -> Bool{
        
        var insertPosition = -1
        for i in 0..<lines.count {
            let line = lines[i]
            if let typeLine = line as? TypeItem {
                if typeLine.itemType == type {
                    insertPosition = i
                    break
                }
            }
        }
        if insertPosition < 0 {
            let typeStr = "[\(type)]"
            lines.append(TypeItem(typeStr))
            insertPosition = lines.count - 1
        }
        
        switch type {
        case .General:
            var find = false
            if let generalItem = item as? GeneralItem {
                for index in insertPosition..<lines.count {
                    if let rule = lines[index] as? GeneralItem {
                        if rule.key == generalItem.key {
                            (lines[index] as? GeneralItem)?.value = generalItem.value
                            find = true
                        }
                    }
                }
            }
            if !find {
                lines.insert(item, at: insertPosition+1)
            }
            break
        case .Other,.Type:
            print("Inset shound not be \(type) !")
            return false
        default:
            lines.insert(item, at: insertPosition+1)
            break
        }
        NotificationCenter.default.post(name: CurrentRuleDidChange, object: "add")
        return true
    }
    
    @discardableResult
    public func move(from: Int, to:Int) -> Bool {
        let line = lines[from]
        if from > to {
            lines.remove(at: from)
            lines.insert(line, at: to)
        }else{
            lines.insert(line, at: to+1)
            lines.remove(at: from)
        }
        NotificationCenter.default.post(name: CurrentRuleDidChange, object: "add")
        return true
    }
    
    @discardableResult
    public func delete(_ type:RuleType, _ index: Int ) -> Bool{
        if lines.count > index , index > 0 {
            let item = lines[index]
            if item.lineType == type {
                lines.remove(at: index)
            }else{
                print("Delete error: \(item.lineType) != \(type)")
                NotificationCenter.default.post(name: CurrentRuleDidChange, object: "delete")
                return false
            }
        }else{
            print("Delete error : index \(index) out of range !")
            NotificationCenter.default.post(name: CurrentRuleDidChange, object: "delete")
            return false
        }
        NotificationCenter.default.post(name: CurrentRuleDidChange, object: "delete")
        return true
    }
    
    @discardableResult
    public func replace(_ type:RuleType, _ item: RuleLine, _ index: Int = -1) -> Bool{
        if lines.count > index , index > 0 {
            let line = lines[index]
            if line.lineType == type {
                lines.remove(at: index)
                lines.insert(item, at: index)
            }else{
                print("Replace error: \(item.lineType) != \(type)")
                NotificationCenter.default.post(name: CurrentRuleDidChange, object: "replace")
                return false
            }
        }else{
            print("Replace error : index \(index) out of range !")
            NotificationCenter.default.post(name: CurrentRuleDidChange, object: "replace")
            return false
        }
        NotificationCenter.default.post(name: CurrentRuleDidChange, object: "replace")
        return true
    }
    
    public func configParse(){
        lines.removeAll()
        let allLines = _config.components(separatedBy: "\n")
        var type:RuleType = .Other
        for index in 0..<allLines.count {
            let line = allLines[index]
            if line.lowercased().starts(with: "[general]"){
                lines.append(TypeItem(line))
                type = .General
                continue
            }
            if line.lowercased().starts(with: "[rule]") {
                lines.append(TypeItem(line))
                type = .Rule
                continue
            }
            if line.lowercased().starts(with: "[host]") {
                lines.append(TypeItem(line))
                type = .Host
                continue
            }
            
            switch type {
            case .General:
                generalParse(line,index)
                continue
            case .Rule:
                ruleParse(line, index)
                continue
            case .Host:
                hostParse(line, index)
                continue
            case .Other:
                otherParse(line, index)
                continue
            case .Type:
                continue
            }
        }
    }
    
    func generalParse(_ line:String, _ index:Int){
        GeneralItem.fromLine(line, success: { (generalLine) in
            switch generalLine.key {
            case "name":
                _name = generalLine.value
            case "default-strategy":
                if let strategyType = Strategy(rawValue: generalLine.value.uppercased()) {
                    _defaultStrategy = strategyType
                }else{
                    _defaultStrategy = .COPY
                    generalLine.value = Strategy.COPY.rawValue
                    print("Warning(\(index)): unknow strategy : \(generalLine.value) !")
                }
            case "default-direct-enable":
                _defaultBlacklistEnable = generalLine.value == "true"
            case "createtime":
                _createTime = generalLine.value
            case "author":
                _author = generalLine.value
            case "note":
                _note = generalLine.value
            default:
                otherParse(line, index)
                print("Warning(\(index)): unknow general key \(generalLine.key) !")
                return
            }
            lines.append(generalLine)
        }) { (errorStr) in
            otherParse(line, index)
            print("Warning(\(index)): is not general line \(errorStr ?? "")!")
        }
    }
    
    func ruleParse(_ line:String, _ index:Int){
        RuleItem.fromLine(line, index, success: { (ruleLine) in
            lines.append(ruleLine)
        }) { (errorStr) in
            otherParse(line, index)
            print("Warning(\(index)): is not rule line \(errorStr ?? "")!")
        }
    }
    
    func hostParse(_ line:String, _ index:Int){
        HostItem.fromLine(line, success: { (hostLine) in
            lines.append(hostLine)
        }) { (errorStr) in
            otherParse(line, index)
            print("Warning(\(index)): is not host line \(errorStr ?? "")!")
        }
    }
    
    func otherParse(_ line:String, _ index:Int){
        lines.append(OtherItem(line))
    }
    
    public func saveToDB()  throws {
        _ = config  // 更新 _congig
        try save()
    }
    
    public static func findRules() -> [Rule] {
        return Rule.findAll()
    }
    
    func matchingDefaultBlacklist(host: String,uri: String, target: String) -> Bool {
        var fullUri = uri
        if uri.hasPrefix("/") {
            fullUri = host + uri
        }
        for item in defaulBlacklistRuleItems {
            switch item.matchRule {
            case .DOMAIN:
                if host.lowercased() == item.value.lowercased() { return true }
            case .DOMAINKEYWORD:
                if host.lowercased().contains(item.value) || fullUri.lowercased().contains(item.value) { return true }
            case .DOMAINSUFFIX:
                if host.lowercased().hasSuffix(item.value.lowercased()) { return true }
            case .URLREGEX:
                guard (try? NSRegularExpression(pattern: item.value, options: .caseInsensitive)) != nil else {
                    print("Invalid Regex")
                    return false
                }
                let pred = NSPredicate(format: "SELF MATCHES %@", item.value)
                if pred.evaluate(with: host) || pred.evaluate(with: fullUri) || pred.evaluate(with: fullUri.urlEncoded()) {
                    return true
                }
            case .USERAGENT:
                if target.lowercased().contains(item.value.lowercased()) || target.lowercased().contains(item.value.urlEncoded()){
                    return true
                }
            case .NONE:
                break
            case .IPCIDR:
                break
            }
        }
        return false
    }
    
    public func matching(host: String,uri: String, target: String) -> Bool {
        if defaultBlacklistEnable, defaultStrategy == .DIRECT {
            // 匹配默认黑名单
            if matchingDefaultBlacklist(host: host, uri: uri, target: target) {
                print("命中默认黑名单:\n**********\n\(host)\n\(target)\n\(uri)\n**********")
                return true
            }
        }
        if _validRuleItems == nil {
            _validRuleItems = validRuleItems
        }
        var fullUri = uri
        if uri.hasPrefix("/") {
            fullUri = host + uri
        }
        for item in _validRuleItems! {
            switch item.matchRule {
            case .DOMAIN:
                if host.lowercased() == item.value.lowercased() {
//                    print("命中DOMAIN(\(item.value)):\n*************************\n\(host)\n\(target)\n\(uri)\n*************************")
                    return true }
            case .DOMAINKEYWORD:
                if host.lowercased().contains(item.value) || fullUri.lowercased().contains(item.value) {
//                    print("命中DOMAINKEYWORD(\(item.value)):\n*************************\n\(host)\n\(target)\n\(uri)\n*************************")
                    return true }
            case .DOMAINSUFFIX:
                if host.lowercased().hasSuffix(item.value.lowercased()) {
//                    print("命中DOMAINSUFFIX(\(item.value)):\n*************************\n\(host)\n\(target)\n\(uri)\n*************************")
                    return true }
            case .URLREGEX:
                guard (try? NSRegularExpression(pattern: item.value, options: .caseInsensitive)) != nil else {
                    print("Invalid Regex")
                    return false
                }
                let pred = NSPredicate(format: "SELF MATCHES %@", item.value)
                if pred.evaluate(with: host) || pred.evaluate(with: fullUri) || pred.evaluate(with: fullUri.urlEncoded()) {
//                    print("命中URLREGEX(\(item.value)):\n*************************\n\(host)\n\(target)\n\(uri)\n*************************")
                    return true
                }
            case .USERAGENT:
                if target.lowercased().contains(item.value.lowercased()) || target.lowercased().contains(item.value.urlEncoded()){
//                    print("命中USERAGENT(\(item.value)):\n*************************\n\(host)\n\(target)\n\(uri)\n*************************")
                    return true
                }
            case .NONE:
                break
            case .IPCIDR:
                break
            }
        }
//        print("未命中:\n*************************\n\(host)\n\(target)\n\(uri)\n*************************")
        return false
    }
    
}

private extension String {
    func urlEncoded() -> String {
        guard let result = self.addingPercentEncoding(withAllowedCharacters: _allowedCharacters) else {
            return "jfaongkxhaugksnxhghrkdghxgiajgnfkhnknxnkjiwoietoi"
        }
        return result
    }
}

private var _allowedCharacters: CharacterSet = {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove("+")
    return allowed
}()
