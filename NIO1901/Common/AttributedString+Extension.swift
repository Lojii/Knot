//
//  AttributedString+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/15.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation
import UIKit

enum Attribute {
    /// 前景色
    case color(UIColor)
    /// 背景色
    case backColor(UIColor)
    /// 字体
    case font(UIFont)
    /// 段落1
    case pStyle(NSMutableParagraphStyle)
    /// 段落2 => 闭包方式
    case pClosure((NSMutableParagraphStyle) -> Void)
    /// 删除线样式
    case strikethrough(NSUnderlineStyle)
    /// 删除线颜色
    case strikethroughColor(UIColor)
    /// 删除线加颜色
    case strikethroughWithColor(NSUnderlineStyle, UIColor)
    /// 下划线样式
    case underline(NSUnderlineStyle)
    /// 下划线颜色
    case underlineColor(UIColor)
    /// 下划线和颜色
    case underlineWithColor(NSUnderlineStyle, UIColor)
    
    var keyValue: [AttributedString.Key: Any] {
        switch self {
        case .color(let color):
            return [.foregroundColor: color]
        case .backColor(let color):
            return [.backgroundColor: color]
        case .font(let font):
            return [.font: font]
        case .pClosure(let closure):
            let pStyle = NSMutableParagraphStyle()
            closure(pStyle)
            return [.paragraphStyle: pStyle]
        case .strikethrough(let style):
            return [.strikethroughStyle: style.rawValue]
        case .strikethroughColor(let color):
            return [.strikethroughColor: color]
        case .strikethroughWithColor(let style, let color):
            return [.strikethroughStyle: style.rawValue, .strikethroughColor: color]
        case .underline(let style):
            return [.underlineStyle: style.rawValue]
        case .underlineColor(let color):
            return [.underlineColor: color]
        case .underlineWithColor(let style, let color):
            return [.underlineStyle: style.rawValue, .underlineColor: color]
        case .pStyle(let style):
            return [.paragraphStyle: style]
        }
    }
}

typealias AttributedString = NSMutableAttributedString

extension AttributedString {
    
    /// 追加属性字符串
    /// 如果传进来的 attrString 不包含 .font 属性，则自动同步上一个的 .font
    @discardableResult
    func append(_ attrString: AttributedString) -> AttributedString {
        append(NSAttributedString(attributedString: attrString))
        if attrString.getAttrs(at: attrString.count - 1)[.font] == nil, let font = getAttrs(at: count - 2)[.font] {
            setAttributes([.font : font], range: getRange(at: count - 2))
        }
        return self
    }
    
    /// 为指定节点范围（默认全部）的内容添加属性
    @discardableResult
    func addAttributes(_ attrs: Attribute..., range: Range<Int>? = nil) -> AttributedString {
        let keyValues = attrs.reduce(into: [:]) { (result, a) in
            result.merge(a.keyValue, uniquingKeysWith: { $1 })
        }
        guard let newRange = range else {
            addAttributes(keyValues, range: NSRange(location: 0, length: length)); return self
        }
        let newLocation = getRange(at: newRange.lowerBound).location
        let newLength = getRange(at: newRange.upperBound - 1).upperBound - newLocation
        addAttributes(keyValues, range: NSRange(location: newLocation, length: newLength))
        return self
    }
    
    /// 为指定节点范围（默认全部）的内容重置属性
    @discardableResult
    func setAttributes(_ attrs: Attribute..., range: Range<Int>? = nil) -> AttributedString {
        let keyValues = attrs.reduce(into: [:]) { (result, a) in
            result.merge(a.keyValue, uniquingKeysWith: { $1 })
        }
        guard let newRange = range else {
            addAttributes(keyValues, range: NSRange(location: 0, length: length)); return self
        }
        let newLocation = getRange(at: newRange.lowerBound).location
        let newLength = getRange(at: newRange.upperBound - 1).upperBound - newLocation
        addAttributes(keyValues, range: NSRange(location: newLocation, length: newLength))
        return self
    }
    
    /// 替换指定节点范围的字符串
    func replace(in range: Range<Int>, with str: String) {
        let location = getRange(at: range.lowerBound).location
        let length = getRange(at: range.upperBound - 1).upperBound - location
        replaceCharacters(in: NSRange(location: location, length: length), with: str)
    }
    
    /// 替换指定节点范围的属性字符串
    func replace(in range: Range<Int>, with attrString: AttributedString) {
        let location = getRange(at: range.lowerBound).location
        let length = getRange(at: range.upperBound - 1).upperBound - location
        replaceCharacters(in: NSRange(location: location, length: length), with: attrString)
    }
    
    /// 删除指定节点范围的属性字符串
    func delete(in range: Range<Int>) {
        let location = getRange(at: range.lowerBound).location
        let length = getRange(at: range.upperBound - 1).upperBound - location
        deleteCharacters(in: NSRange(location: location, length: length))
    }
    
    /// 设置/获取指定节点处的属性字符串
    subscript(node: Int) -> AttributedString {
        get { return AttributedString(attributedString: attributedSubstring(from: getRange(at: node))) }
        set { replaceCharacters(in: getRange(at: node), with: newValue) }
    }
}

public extension NSAttributedString {
    
    /// 获取指节点处的字符串属性
    func getAttrs(at node: Int) -> [NSAttributedString.Key: Any] {
        return attributes(at: getRange(at: node).location, effectiveRange: nil)
    }
    
    /// 返回所有节点个数
    var count: Int {
        var offset = 0
        enumerateAttributes(in: NSRange(location: 0, length: length)) { (_, _, _) in offset += 1 }
        return offset
    }
    
    /// 获取指定节点的所在范围
    func getRange(at node: Int) -> NSRange {
        var findRange: NSRange?
        var offset = 0
        enumerateAttributes(in: NSRange(location: 0, length: length)) { (_, range, stop) in
            if offset == node {
                findRange = range
                stop.pointee = true; return // 停止继续遍历
            }
            offset += 1
        }
        return findRange!
    }
}
