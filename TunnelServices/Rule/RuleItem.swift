//
//  RuleItem.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

public class RuleItem: RuleLine {
    
    public var matchRule:MatchRule = .NONE
    public var value:String = "-"
    public var strategy:Strategy = .NONE
    public var other:String?
    public var annotation:String?
    public var index:Int = -1
    
    override public init() {
        super.init()
    }
    
    static func == (lhs: RuleItem, rhs: RuleItem) -> Bool {
        return lhs._line == rhs._line
    }
    
    override func lineDidSet() {
        
    }
    
    override func lineWillGet() {
        _line = "\(matchRule.rawValue), \(value), \(strategy.rawValue)"
        if other != nil, other != "" {
            _line.append(", \(other!)")
        }
        if annotation != nil,annotation != "" {
            _line.append(" //\(annotation!)")
        }
    }
    
    public static func fromLine(_ line:String,_ index:Int = -1, success:((RuleItem) -> Void), failure:((String?) -> Void) ) -> Void {
        if line == "" {
            failure(nil)
            return
        }
        
        let item = RuleItem()
        item.lineType = .Rule
        item.index = index
        var parts = line.components(separatedBy: "//")
        // 有效部分
        let payload = parts[0]
        if payload.trimmingCharacters(in: .whitespaces) == "" {
            failure(nil)
            return
        }
        // 注释
        parts.removeFirst()
        let annotation = parts.joined(separator: "//")
        item.annotation = annotation
        // 解析有效部分  //type, value, strategy //note    类型， 匹配值， 策略 //备注
        var ruleParts = payload.components(separatedBy: ",")
        if ruleParts.count == 0 {
            failure("no rule params in \(payload)")
            return
        }
        // type
        if let matchStr = ruleParts.first?.trimmingCharacters(in: .whitespaces).uppercased() {
            if let mr = MatchRule(rawValue: matchStr) {
                item.matchRule = mr
            }else{
                failure("error MatchRule :\(ruleParts.first ?? "")")
                return
            }
            ruleParts.removeFirst()
        }else{
            failure("no MatchRule in \(payload)")
            return
        }
        // value
        if let valueStr = ruleParts.first?.trimmingCharacters(in: .whitespaces) {
            item.value = valueStr
            ruleParts.removeFirst()
        }else{
            failure("no value in \(payload)")
            return
        }
        // strategy
        if let strategyStr = ruleParts.first?.trimmingCharacters(in: .whitespaces).uppercased() {
            if let strategy = Strategy(rawValue: strategyStr) {
                item.strategy = strategy
            }else{
                failure("error Strategy :\(strategyStr)")
                return
            }
            ruleParts.removeFirst()
        }else{
            failure("no strategy in \(payload)")
            return
        }
        // others
        if ruleParts.count > 0 {
            item.other = ruleParts.joined(separator: ",").trimmingCharacters(in: .whitespaces)
        }
        success(item)
    }

    
    
//    # 触发通知，匹配规则时弹出 notification-text 定义的字符串
//    DOMAIN-SUFFIX,scomper.me,DIRECT,notification-text="Welcome to scomper's blog."
    // type, value, strategy //note    类型， 匹配值， 策略 //备注
    // DOMAIN-KEYWORD,usage,REJECT
}
