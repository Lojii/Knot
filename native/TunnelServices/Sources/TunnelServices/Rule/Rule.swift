//
//  Rule.swift
//  Knot
//
//  Created by LiuJie on 2019/6/7.
//  Copyright © 2019 Lojii. All rights reserved.
//
//  NOTE: The legacy Rule class (ASModel subclass) has been removed.
//  Rule management now uses RuleRecord + CatalogDAO.
//  Shared enums and RuleLine remain here for RuleEngine and UI code.

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
