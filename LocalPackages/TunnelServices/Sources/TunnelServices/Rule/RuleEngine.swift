//
//  RuleEngine.swift
//  Knot
//
//  Extracted from Rule.swift to decouple rule parsing/matching from the database model.
//

import Foundation

/// Standalone rule engine that parses a config string and performs host/URI matching.
/// Does not depend on ASModel or any database layer.
public class RuleEngine {

    // MARK: - Parsed state

    public private(set) var name: String = ""
    public private(set) var defaultStrategy: Strategy = .COPY
    public private(set) var defaultBlacklistEnable: Bool = true
    public private(set) var createTime: String = ""
    public private(set) var author: String?
    public private(set) var note: String?

    public var lines = [RuleLine]()

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

    private var _cachedRuleItems: [RuleItem]?

    // MARK: - Default blacklist

    public lazy var defaultBlacklistRuleItems: [RuleItem] = {
        var blackItems = [RuleItem]()
        if let certDir = MitmService.getCertPath() {
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

    // MARK: - Init

    public init(config: String) {
        configParse(config)
    }

    // MARK: - Parsing

    public func configParse(_ config: String) {
        lines.removeAll()
        _cachedRuleItems = nil
        let allLines = config.components(separatedBy: "\n")
        var type: RuleType = .Other
        for index in 0..<allLines.count {
            let line = allLines[index]
            if line.lowercased().starts(with: "[general]") {
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
                generalParse(line, index)
            case .Rule:
                ruleParse(line, index)
            case .Host:
                hostParse(line, index)
            case .Other:
                otherParse(line, index)
            case .Type:
                break
            }
        }
    }

    private func generalParse(_ line: String, _ index: Int) {
        GeneralItem.fromLine(line, success: { (generalLine) in
            switch generalLine.key {
            case "name":
                self.name = generalLine.value
            case "default-strategy":
                if let strategyType = Strategy(rawValue: generalLine.value.uppercased()) {
                    self.defaultStrategy = strategyType
                } else {
                    self.defaultStrategy = .COPY
                    generalLine.value = Strategy.COPY.rawValue
                    print("Warning(\(index)): unknow strategy : \(generalLine.value) !")
                }
            case "default-direct-enable":
                self.defaultBlacklistEnable = generalLine.value == "true"
            case "createtime":
                self.createTime = generalLine.value
            case "author":
                self.author = generalLine.value
            case "note":
                self.note = generalLine.value
            default:
                self.otherParse(line, index)
                print("Warning(\(index)): unknow general key \(generalLine.key) !")
                return
            }
            self.lines.append(generalLine)
        }) { (errorStr) in
            self.otherParse(line, index)
            print("Warning(\(index)): is not general line \(errorStr ?? "")!")
        }
    }

    private func ruleParse(_ line: String, _ index: Int) {
        RuleItem.fromLine(line, index, success: { (ruleLine) in
            self.lines.append(ruleLine)
        }) { (errorStr) in
            self.otherParse(line, index)
            print("Warning(\(index)): is not rule line \(errorStr ?? "")!")
        }
    }

    private func hostParse(_ line: String, _ index: Int) {
        HostItem.fromLine(line, success: { (hostLine) in
            self.lines.append(hostLine)
        }) { (errorStr) in
            self.otherParse(line, index)
            print("Warning(\(index)): is not host line \(errorStr ?? "")!")
        }
    }

    private func otherParse(_ line: String, _ index: Int) {
        lines.append(OtherItem(line))
    }

    // MARK: - Matching

    func matchingDefaultBlacklist(host: String, uri: String, target: String) -> Bool {
        var fullUri = uri
        if uri.hasPrefix("/") {
            fullUri = host + uri
        }
        for item in defaultBlacklistRuleItems {
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
                if pred.evaluate(with: host) || pred.evaluate(with: fullUri) || pred.evaluate(with: fullUri.ruleUrlEncoded()) {
                    return true
                }
            case .USERAGENT:
                if target.lowercased().contains(item.value.lowercased()) || target.lowercased().contains(item.value.ruleUrlEncoded()) {
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

    public func matching(host: String, uri: String, target: String) -> Bool {
        if defaultBlacklistEnable, defaultStrategy == .DIRECT {
            if matchingDefaultBlacklist(host: host, uri: uri, target: target) {
                print("命中默认黑名单:\n**********\n\(host)\n\(target)\n\(uri)\n**********")
                return true
            }
        }
        if _cachedRuleItems == nil {
            _cachedRuleItems = validRuleItems
        }
        var fullUri = uri
        if uri.hasPrefix("/") {
            fullUri = host + uri
        }
        for item in _cachedRuleItems! {
            switch item.matchRule {
            case .DOMAIN:
                if host.lowercased() == item.value.lowercased() {
                    return true
                }
            case .DOMAINKEYWORD:
                if host.lowercased().contains(item.value) || fullUri.lowercased().contains(item.value) {
                    return true
                }
            case .DOMAINSUFFIX:
                if host.lowercased().hasSuffix(item.value.lowercased()) {
                    return true
                }
            case .URLREGEX:
                guard (try? NSRegularExpression(pattern: item.value, options: .caseInsensitive)) != nil else {
                    print("Invalid Regex")
                    return false
                }
                let pred = NSPredicate(format: "SELF MATCHES %@", item.value)
                if pred.evaluate(with: host) || pred.evaluate(with: fullUri) || pred.evaluate(with: fullUri.ruleUrlEncoded()) {
                    return true
                }
            case .USERAGENT:
                if target.lowercased().contains(item.value.lowercased()) || target.lowercased().contains(item.value.ruleUrlEncoded()) {
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
}

// MARK: - Internal URL encoding helper (shared with Rule.swift)

private var _ruleAllowedCharacters: CharacterSet = {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove("+")
    return allowed
}()

internal extension String {
    func ruleUrlEncoded() -> String {
        guard let result = self.addingPercentEncoding(withAllowedCharacters: _ruleAllowedCharacters) else {
            return "jfaongkxhaugksnxhghrkdghxgiajgnfkhnknxnkjiwoietoi"
        }
        return result
    }
}
