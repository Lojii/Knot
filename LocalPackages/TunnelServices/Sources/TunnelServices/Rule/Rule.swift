//
//  Rule.swift
//  Knot
//
//  Created by LiuJie on 2019/6/7.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation

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

    // MARK: - RuleEngine (delegates parsing & matching)

    private lazy var engine: RuleEngine = {
        RuleEngine(config: self._config)
    }()

    // [General]
    public var defaulBlacklistRuleItems: [RuleItem] {
        return engine.defaultBlacklistRuleItems
    }

    var _validRuleItems:[RuleItem]?
    public var validRuleItems: [RuleItem] {
        return engine.validRuleItems
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

    public var lines: [RuleLine] {
        get { return engine.lines }
        set { /* lines are managed by engine after parsing */ }
    }
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
            // 解析规则配置 via engine
            engine.configParse(_config)
            // Sync parsed general values back to Rule properties
            _name = engine.name
            _defaultStrategy = engine.defaultStrategy
            _defaultBlacklistEnable = engine.defaultBlacklistEnable
            _createTime = engine.createTime
            _author = engine.author
            _note = engine.note
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
        for i in 0..<engine.lines.count {
            let line = engine.lines[i]
            if let typeLine = line as? TypeItem {
                if typeLine.itemType == type {
                    insertPosition = i
                    break
                }
            }
        }
        if insertPosition < 0 {
            let typeStr = "[\(type)]"
            engine.lines.append(TypeItem(typeStr))
            insertPosition = engine.lines.count - 1
        }

        switch type {
        case .General:
            var find = false
            if let generalItem = item as? GeneralItem {
                for index in insertPosition..<engine.lines.count {
                    if let rule = engine.lines[index] as? GeneralItem {
                        if rule.key == generalItem.key {
                            (engine.lines[index] as? GeneralItem)?.value = generalItem.value
                            find = true
                        }
                    }
                }
            }
            if !find {
                engine.lines.insert(item, at: insertPosition+1)
            }
            break
        case .Other,.Type:
            print("Inset shound not be \(type) !")
            return false
        default:
            engine.lines.insert(item, at: insertPosition+1)
            break
        }
        NotificationCenter.default.post(name: CurrentRuleDidChange, object: "add")
        return true
    }

    @discardableResult
    public func move(from: Int, to:Int) -> Bool {
        let line = engine.lines[from]
        if from > to {
            engine.lines.remove(at: from)
            engine.lines.insert(line, at: to)
        }else{
            engine.lines.insert(line, at: to+1)
            engine.lines.remove(at: from)
        }
        NotificationCenter.default.post(name: CurrentRuleDidChange, object: "add")
        return true
    }

    @discardableResult
    public func delete(_ type:RuleType, _ index: Int ) -> Bool{
        if engine.lines.count > index , index > 0 {
            let item = engine.lines[index]
            if item.lineType == type {
                engine.lines.remove(at: index)
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
        if engine.lines.count > index , index > 0 {
            let line = engine.lines[index]
            if line.lineType == type {
                engine.lines.remove(at: index)
                engine.lines.insert(item, at: index)
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
        engine.configParse(_config)
        // Sync parsed general values back to Rule properties
        _name = engine.name
        _defaultStrategy = engine.defaultStrategy
        _defaultBlacklistEnable = engine.defaultBlacklistEnable
        _createTime = engine.createTime
        _author = engine.author
        _note = engine.note
    }

    public func saveToDB()  throws {
        _ = config  // 更新 _congig
        try save()
    }

    public static func findRules() -> [Rule] {
        return Rule.findAll()
    }

    public func matching(host: String,uri: String, target: String) -> Bool {
        return engine.matching(host: host, uri: uri, target: target)
    }

}
