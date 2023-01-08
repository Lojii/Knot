//
//  Color+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

///RGBA
func RGBA(r:CGFloat,g:CGFloat,b:CGFloat,a:CGFloat) ->UIColor{
    return UIColor(red: r/225.0, green: g/225.0, blue: b/225.0, alpha: a)
}
///RGB
func RGB(r:CGFloat,g:CGFloat,b:CGFloat) ->UIColor{
    return UIColor(red: r/225.0, green: g/225.0, blue: b/225.0, alpha: 1.0)
}
///随机色
func randomColor() ->  UIColor{
    let r = Int(arc4random_uniform(255))
    let g = Int(arc4random_uniform(255))
    let b = Int(arc4random_uniform(255))
    return RGB(r: CGFloat(r), g: CGFloat(g), b: CGFloat(b))
}

extension UIColor{
    public convenience init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt32()
        Scanner(string: hex).scanHexInt32(&int)
        let a, r, g, b: UInt32
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
    
    /// 使用Int值快速创建颜色
    public convenience init(redValue: Int, green: Int, blue: Int, alpha: CGFloat) {
        self.init(red: CGFloat(redValue) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: alpha)
    }
    
    /// rgb数组
    public func convertRGB() -> [Int]? {
        var fRed : CGFloat = 0
        var fGreen : CGFloat = 0
        var fBlue : CGFloat = 0
        var fAlpha: CGFloat = 0
        if self.getRed(&fRed, green: &fGreen, blue: &fBlue, alpha: &fAlpha) {
            let iRed = Int(fRed * 255.0)
            let iGreen = Int(fGreen * 255.0)
            let iBlue = Int(fBlue * 255.0)
            //            let iAlpha = Int(fAlpha * 255.0)
            return [iRed, iGreen, iBlue]
        } else {
            // Could not extract RGBA components:
            return [13, 122, 255]
        }
    }
    
    ///随机色
    public static func random(randomAlpha: Bool = false) -> UIColor {
        let randomRed = arc4random()%255
        let randomGreen = arc4random()%255
        let randomBlue = arc4random()%255
        let alpha = randomAlpha ? arc4random()%255 : 1
        return RGBA(CGFloat(randomRed), CGFloat(randomGreen), CGFloat(randomBlue), CGFloat(alpha))
    }
    
    /// rgba
    public static func RGBA(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> UIColor {
        return UIColor(red: r/255, green: g/255, blue: b/255, alpha: a)
    }
    /// rgb
    public static func RGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        return RGBA(r, g, b, 1.0)
    }
    ///UIColor转化为16进制
    public var hex: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        var rgb: Int = (Int)(red * 255) << 16 | (Int)(green * 255) << 8
        rgb = rgb | (Int)(blue * 255) << 0
        
        return String(format: "#%06x", rgb)
    }
    ///16进制转rgb
    public convenience init?(hexString: String, alpha: CGFloat = 1.0) {
        var formatted = hexString.replacingOccurrences(of: "0x", with: "")
        formatted = formatted.replacingOccurrences(of: "#", with: "")
        if let hex = Int(formatted, radix: 16) {
            let red = CGFloat(CGFloat((hex & 0xFF0000) >> 16)/255.0)
            let green = CGFloat(CGFloat((hex & 0x00FF00) >> 8)/255.0)
            let blue = CGFloat(CGFloat((hex & 0x0000FF) >> 0)/255.0)
            self.init(red: red, green: green, blue: blue, alpha: alpha)        } else {
            return nil
        }
    }
    
}

