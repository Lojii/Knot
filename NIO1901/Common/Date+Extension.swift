//
//  Date+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

extension Formatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}

//MARK:-- 常用方法 --
extension Date{
    
    var iso8601: String {
        return Formatter.iso8601.string(from: self)
    }
    
    ///获取当前时间字符串
    var dateName:String{
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYYMMdd-HHmmss"
        let dataString = dateFormatter.string(from: self)
        return dataString
    }
    
    ///获取当前时间字符串
    var MMDDStr:String{
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd"
        let dataString = dateFormatter.string(from: self)
        return dataString
    }
    
    ///获取当前时间字符串
    public var CurrentStingTime:String{
        let dateFormatter = DateFormatter.init()
        dateFormatter.dateFormat = "MM-dd HH:mm:ss"//"YYYY-MM-dd HH:mm:ss"
        let dataString = dateFormatter.string(from: self)
        return dataString
    }
    
    ///获取当前时间字符串
    public var CurrentStingTimeForCell:String{
        let dateFormatter = DateFormatter.init()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"//"YYYY-MM-dd HH:mm:ss"
        let dataString = dateFormatter.string(from: self)
        return dataString
    }
    
    /// 获取当前时间 date
    public var CurrentDateTime:Date{
        let date = Date.init(timeInterval: 60*60*8, since: self)
        return date
    }
    
    ///获取当前时间戳
    public var CurrentStampTime:u_long{
        let date = Date.init(timeInterval: 0, since: self)
        let stamp = date.timeIntervalSince1970
        return u_long(stamp)
    }
    ///获取当天0点时间戳
    public var todayZeroStampTime:u_long{
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd"
        let dateString = dateFormatter.string(from: currentDate)
        let zeroStr = dateString + " 00:00:00"
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss"
        
        let date = dateFormatter.date(from: zeroStr)
        
        return (date?.StampTime(from: date!))!
    }
    
    
    /// date 转化为时间戳
    func StampTime(from date:Date) ->  u_long{
        return u_long(date.timeIntervalSince1970)
    }
    ///date 转字符串
    func dateString(from date:Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateS = formatter.string(from: date)
        return dateS
        
    }
    
    /// 时间戳转化为date
    func date(from StampTime:u_long) -> Date {
        //转换为时间
        let timeInterval:TimeInterval = TimeInterval(StampTime)
        let date = NSDate(timeIntervalSince1970: timeInterval + 8*60*60)
        return date as Date
    }
    /// 时间戳转化为字符串
    func dateString(from StampTime:u_long) -> String {
        
        let timeInterval:TimeInterval = TimeInterval(StampTime)
        let date = NSDate(timeIntervalSince1970: timeInterval + 8*60*60)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateS = formatter.string(from: date as Date)
        
        return dateS
    }
    /// 字符串转date
    func date(from dateString:String) -> Date {
        let dateFormatter = DateFormatter.init()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let date = dateFormatter.date(from: dateString)
        
        return date!
    }
    /// 字符串转时间戳
    func StampTime(from dateString:String) ->  u_long{
        let dateFormatter = DateFormatter.init()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let date = dateFormatter.date(from: dateString)
        let stamp = date!.timeIntervalSince1970 - 8*60*60
        
        return u_long(stamp)
    }
    
    
}
//MARK: -- 其他 --
extension Date{
    /// 年
    public var year: Int {
        return NSCalendar.current.component(.year, from: self)
    }
    /// 月
    public var month: Int {
        return NSCalendar.current.component(.month, from: self)
    }
    /// 日
    public var day: Int {
        return NSCalendar.current.component(.day, from: self)
    }
    /// 周几
    public var weekday: String {
        let weekdays = [NSNull.init(),"星期天","星期一","星期二","星期三","星期四","星期五","星期六"] as [Any]
        var calendar = Calendar(identifier:.gregorian)
        
        let timeZone = NSTimeZone.init(name: "Asia/Shanghai")
        
        calendar.timeZone = timeZone! as TimeZone
        
        let theComponents = calendar.dateComponents([.year,.month, .day,.weekday, .hour,.minute,.second], from: self)
        
        return weekdays[theComponents.weekday!] as! String
    }
    
    /// 是否在将来
    public var isFuture: Bool {
        return self > Date()
    }
    
    /// 是否在过去
    public var isPast: Bool {
        return self < Date()
    }
    /// 是否是今天
    public var isToday: Bool {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: self) == format.string(from: Date())
    }
    
    /// 是否是昨天
    public var isTomorrow: Bool {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        return format.string(from: self) == format.string(from: tomorrow!)
    }
    
}
