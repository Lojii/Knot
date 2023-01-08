//
//  String+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
//MARK:-- 字符串的拆分 --
extension String{
    
    var localized:String {
        return NSLocalizedString(self, comment: "")
    }
    
    func isEmpty() -> Bool{
        return (self == "")
    }
    
    ///  字符串的截取
    public func subStringFrom(index: Int,length:Int) -> String {
        if self.count > index {
            let startIndex = self.index(self.startIndex, offsetBy: index)
            let endIndex = self.index(self.startIndex, offsetBy: index+length)
            
            let subString = self[startIndex..<endIndex]
            return String(subString)
        } else {
            return self
        }
    }
    ///  字符串的截取
    func subString(from: Int, to: Int) -> String
    {
        let fromIndex = index(startIndex, offsetBy: from)
        let toIndex = index(startIndex, offsetBy: to)
        
        guard fromIndex >= startIndex, fromIndex < toIndex, toIndex <= endIndex else { return "" }
        
        return String(self[fromIndex ..< toIndex])
    }
    ///  字符串的截取
    public func substring(from: Int?, to: Int?) -> String
    {
        return substring(from: from ?? 0, to: to ?? count)
    }
    ///  字符串的截取
    func subString(from: Int) -> String
    {
        return substring(from: from, to: nil)
    }
    ///  字符串的截取
    func subString(to: Int) -> String
    {
        return substring(from: nil, to: to)
    }
    
    ///替换指定范围内的字符串
    mutating func stringByReplacingCharactersInRange(index:Int,length:Int,replacText:String) -> String {
        let startIndex = self.index(self.startIndex, offsetBy: index)
        self.replaceSubrange(startIndex..<self.index(startIndex, offsetBy: length), with: replacText)
        return self
    }
    /// 替换指定字符串
    mutating func stringByReplacingstringByReplacingString(text:String,replacText:String) -> String {
        return self.replacingOccurrences(of: text, with: replacText)
    }
    
    ///删除最后一个字符
    mutating func deleteEndCharacters() -> String {
        self.remove(at: self.index(before: self.endIndex))
        return self
    }
    /// 删除指定字符串
    mutating func deleteString(string:String) -> String {
        return self.replacingOccurrences(of: string, with: "")
    }
    
    /// 字符的插入
    mutating func insertString(text:Character,index:Int) -> String{
        let start = self.index(self.startIndex, offsetBy: index)
        self.insert(text, at: start)
        return self
    }
    ///字符串的插入
    mutating func insertString(text:String,index:Int) -> String{
        let start = self.index(self.startIndex, offsetBy: index)
        self.insert(contentsOf: text, at: start)
        return self
    }
    
    /// 将字符串通过特定的字符串拆分为字符串数组
    ///
    /// - Parameter string: 拆分数组使用的字符串
    /// - Returns: 字符串数组
    func split(string:String) -> [String] {
        return NSString(string: self).components(separatedBy: string)
    }
    
}

//MARK: -- 类型判断 --
extension String{
    /// URL编码
    public var eurlEncoded: String {
        let characterSet = CharacterSet(charactersIn: ":/?#[]@!$ &'()*+,;=\"<>%{}|\\^~`")
        return self.addingPercentEncoding(withAllowedCharacters: characterSet)!
        
    }
    /// URL解码
    public var eurlDecode: String? {
        return self.removingPercentEncoding
    }
    
    /// base64编码
    var base64: String {
        let plainData = (self as NSString).data(using: String.Encoding.utf8.rawValue)
        let base64String = plainData!.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
        return base64String
    }
    /// Base64解码
    public var base64Decode: String? {
        
        if let data = Data(base64Encoded: self) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    ///是否是邮箱
    public var isEmail: Bool {
        return range(of: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression, range: nil, locale: nil) != nil }
    /// 是否是URL
    public var isValidUrl: Bool {
        return URL(string: self) != nil }
    /// 是否是手机号
    public var isMobile: Bool {
        guard !self.isEmpty else{
            return false
        }
        let phoneRegix = "[123456789][0-9]{8}([0-9]{1})?"
        let phoneTest = NSPredicate(format: "SELF MATCHES %@", phoneRegix)
        return phoneTest.evaluate(with: self)
    }
    /// 是否是字母数字的组合
    var isAlphanumeric: Bool {
        return !isEmpty && range(of: "[^a-zA-Z0-9]", options: .regularExpression) == nil
    }
    
}

//MARK: -- 将字符串替换成值类型 --
extension String{
    
    ///变成Int 类型
    public func toInt() -> Int? {
        if let num = NumberFormatter().number(from: self) {
            return num.intValue
        } else {
            return nil
        }
    }
    /// 变成Double 类型
    public func toDouble() -> Double? {
        if let num = NumberFormatter().number(from: self) {
            return num.doubleValue
        } else {
            return nil
        }
    }
    /// 变成Float 类型
    public func toFloat() -> Float? {
        if let num = NumberFormatter().number(from: self) {
            return num.floatValue
        } else {
            return nil
        }
    }
}

//MARK:-- 获取文本的宽高 --
extension String{
    /// 获取文本高度
    ///
    /// - Parameters:
    ///   - font: font
    ///   - fixedWidth: fixedWidth
    func textHeight(font : UIFont = UIFont.systemFont(ofSize: 18), fixedWidth : CGFloat) -> CGFloat {
        
        guard self.count > 0 && fixedWidth > 0 else {
            return 0
        }
        let size = CGSize(width:fixedWidth, height:CGFloat.greatestFiniteMagnitude)
        let text = self as NSString
        let rect = text.boundingRect(with: size, options:.usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font : font], context:nil)
        return rect.size.height
    }
    
    
    /// 获取文本宽度
    ///
    /// - Parameter font: font
    func textWidth(font : UIFont = UIFont.systemFont(ofSize: 17)) -> CGFloat {
        
        guard self.count > 0 else {
            return 0
        }
        
        let size = CGSize(width:CGFloat.greatestFiniteMagnitude, height:0)
        let text = self as NSString
        let rect = text.boundingRect(with: size, options:.usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font : font], context:nil)
        return rect.size.width
    }
    
    func textHeight( width: CGFloat, textAttributes: [NSAttributedString.Key : Any]) -> CGFloat {
        guard self.count > 0 && width > 0 else {
            return 0
        }
        let size = CGSize(width:width, height:CGFloat.greatestFiniteMagnitude)
        let text = NSAttributedString(string: self, attributes: textAttributes)
        let rect = text.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)
        return rect.size.height
    }
    
    //MARK:获得string内容高度
    func stringHeightWith(font:UIFont,width:CGFloat,lineSpace : CGFloat)->CGFloat{
//        let font = UIFont.systemFont(ofSize: fontSize)//
        let size = CGSize(width: width, height: CGFloat(MAXFLOAT))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpace
        paragraphStyle.lineBreakMode = .byCharWrapping
        let attributes = [NSAttributedString.Key.font:font, NSAttributedString.Key.paragraphStyle:paragraphStyle.copy()]
        let text = self as NSString
        let rect = text.boundingRect(with: size, options:.usesLineFragmentOrigin, attributes: attributes, context:nil)
        return rect.size.height
        
    }
    
}

extension String {
    
    /// 添加属性 (属性列表方式)
    func addAttributes(_ attrs: Attribute...) -> AttributedString {
        let attrs = attrs.reduce(into: [NSAttributedString.Key: Any]()) { (result, attr) in
            result.merge(attr.keyValue, uniquingKeysWith: { $1 })
        }
        return AttributedString(string: self, attributes: attrs)
    }
    
    /// 添加属性 (数组方式)
    func addAttributes(_ attrs: [Attribute]) -> AttributedString {
        let attrs = attrs.reduce(into: [NSAttributedString.Key: Any]()) { (result, attr) in
            result.merge(attr.keyValue, uniquingKeysWith: { $1 })
        }
        return AttributedString(string: self, attributes: attrs)
    }
    
    /// 转换成属性字符串
    var attrString: AttributedString {
        return AttributedString(string: self)
    }
    
    /// 转换成 HTML 格式的属性字符串
    var html: AttributedString? {
        do {
            return try AttributedString(data: data(using: .unicode)!,
                                        options: [.documentType : NSAttributedString.DocumentType.html],
                                        documentAttributes: nil)
        }catch {
            debugPrint(error)
            return nil
        }
    }
}

// 缓存的用于计算高度的Label
var tempLabelForCalc: UILabel = {
    let label = UILabel()
    label.font = UIFont.systemFont(ofSize: 14)
    label.numberOfLines = 0
    return label
}()


// 计算富文本高度最终版办法，使用sizeThatFits获取Label最终高度
extension String {
    
    func finalSize(_ font: UIFont, _ size: CGSize, _ lines: Int = 0) -> CGSize {
        tempLabelForCalc.numberOfLines = lines
        tempLabelForCalc.font = font
        tempLabelForCalc.text = self
        return tempLabelForCalc.sizeThatFits(size)
    }
   
}

extension NSAttributedString {
    
    func finalSize(_ font: UIFont, _ size: CGSize, _ lines: Int = 0) -> CGSize {
        tempLabelForCalc.numberOfLines = lines
        tempLabelForCalc.font = font
        tempLabelForCalc.attributedText = self
        return tempLabelForCalc.sizeThatFits(size)
    }

}

public extension String{
    
    func isNumber() -> Bool {
//        return NSPredicate(format: "SELF MATCHES ^[0-9]+$").evaluate(with: self)
        let pattern = "^[0-9]+$"
        if NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: self) {
            return true
        }
        return false
    }
    
    func getRealType() -> String {
        if let t = self.components(separatedBy: ";").first {
            if let realType = t.components(separatedBy: "/").last {
                if realType.lowercased() == "text" {
                    return "txt"
                }
                if realType.lowercased() == "javascript" {
                    return "js"
                }
                return realType
            }
        }
        return ""
    }
    
    func getFileName() -> String {
        let uriParts = self.components(separatedBy: "?")
        if let fpart = uriParts.first {
            let paths = fpart.components(separatedBy: "/")
            if let lastPath = paths.last{
                return lastPath
            }
        }
        return ""
    }
    
//    /// URL编码
//    func urlEncoded() -> String {
//        let characterSet = CharacterSet(charactersIn: ":/?#[]@!$ &'()*+,;=\"<>%{}|\\^~`")
//        return self.addingPercentEncoding(withAllowedCharacters: characterSet)!
//    }
//    /// URL解码
//    func urlDecode() -> String? {
//        return self.removingPercentEncoding
//    }
}
