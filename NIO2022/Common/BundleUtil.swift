//
//  BundleUtil.swift
//  PopupAlert-iOS
//
//  Created by darren on 2017/8/2.
//  Copyright © 2017年 陈亮陈亮. All rights reserved.
//

import UIKit
import Foundation

class BundleUtil {
    
    static func getCurrentBundle() -> Bundle{
                
        let podBundle = Bundle(for: IDealistConfig.self)
        
        let bundleURL = podBundle.url(forResource: "IDealist", withExtension: "bundle")
        
        if bundleURL != nil {
            let bundle = Bundle(url: bundleURL!)!
            return bundle
        }else{
            return Bundle.main
        }
    }
    
    static func cl_localizedStringForKey(key: String) -> String {
        return self.cl_localizedStringForKey(key: key, value: "")
    }
    
    static func cl_localizedStringForKey(key: String,value:String) -> String {
        var bundle: Bundle? = nil
        
        if bundle == nil {
            var language = NSLocale.preferredLanguages.first
            let r: Range? = language?.range(of: "zh-Hans")
            if r != nil {
                language = "zh-Hans"
            } else {
                language = "en"
            }
            
            bundle = Bundle(path: self.getCurrentBundle().path(forResource: language, ofType: "lproj")!)
        }
        
        let str = bundle?.localizedString(forKey: key, value: value, table: nil)
        return str ?? ""
    }
}
