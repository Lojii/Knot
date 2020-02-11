//
//  AxEnvHelper.swift
//  QoodCore
//
//  Created by peng(childhood@me.com) on 15/7/8.
//  Copyright (c) 2015年 xiaop. All rights reserved.
//

//import UIKit
#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

import CoreTelephony
import SystemConfiguration
@objc public class AxEnvHelper:NSObject{
#if os(iOS)
    static var reachAiblity =  Reachability()
#endif
    @objc public static func platform() -> String {
        var size : Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: Int(size))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let platform : String = String(cString: machine)
        return platform
    }
    @objc public static func systemName() ->String{
#if os(iOS)
        return UIDevice.current.systemName
#else
        return "OS X"
#endif
    }
    @objc public static func deviceName() -> String{
#if os(iOS)
        return UIDevice.current.name
#else
        return "Macintosh"
#endif
    }
    @objc public static func systemVersion() -> String{
#if os(iOS)
        return UIDevice.current.systemVersion
#else
        return "10.11"
#endif
    }
    @objc public static func appVersion() -> String{
        if let info = Bundle.main.infoDictionary, let appVersion =  info["CFBundleShortVersionString"] as? String{
            return appVersion
        }
        return ""
    }
    @objc public static func appBuild() -> String{
        if let info = Bundle.main.infoDictionary, let buildVersion =  info["CFBundleVersion"] as? String{
            return buildVersion
        }
        return ""
    }
    @objc public static func deviceModel() -> String{
        
#if os(iOS)
            return UIDevice.current.model
#else
            return "10.11"
#endif
    }
    @objc public static func deviceLocalizedModel() -> String{
#if os(iOS)
            return UIDevice.current.localizedModel
#else
            return "10.11"
#endif
    }
    @objc public static func phoneIdentifier() -> String{
        
        #if os(iOS)
            return UIDevice.current.identifierForVendor!.uuidString
        #else
            return "10.11"
        #endif
    }
    @objc public static func appIdentifier() -> String{
        if let identifier = Bundle.main.bundleIdentifier{
            return identifier
        }
        return ""
    }
    @objc public static func screenSize() -> String{
        
        #if os(iOS)
//            let width = UIScreen.main.scale * UIScreen.main.bounds.size.width
//            let height = UIScreen.main.scale * UIScreen.main.bounds.size.height
            return "1024"//\(width)*\(height)"
        #else
            return "10.11"
        #endif
    }
    @objc public static func carrier() -> String{
        
        #if os(iOS)
//            let carrier = CTTelephonyNetworkInfo().subscriberCellularProvider
//            if carrier != nil{
//                return "\(carrier!.mobileCountryCode)\(carrier!.mobileNetworkCode)"
//            }
            return "unknow"
        #else
            return "unknow"
        #endif
    }
    
    @objc public static func networkType() -> String{
        #if os(iOS)
//            let staus: NetworkStatus = reachAiblity!.currentReachabilityStatus
//            if  staus == .isReachableViaWiFi{
//                return "CELL"//CTTelephonyNetworkInfo().currentRadioAccessTechnology!.stringByReplacingOccurrencesOfString("CTRadioAccessTechnology", withString: "", options: NSString.CompareOptions.LiteralSearch, range: nil)
//            }else if staus == .isReachableViaWiFi{
//                return "wifi"
//            }
            return "noconnection"
        #else
            return "noconnection"
        #endif
        
    }
    @objc public static func infoDict() -> [String:String]{
        var dict = [String:String]()
        dict["platform"] = self.platform()
        dict["system_name"] = self.systemName()
        dict["device_name"] = self.deviceName()
        dict["system_version"] = self.systemVersion()
        dict["app_version"] = self.appVersion()
        dict["app_build"] = self.appBuild()
        dict["device_model"] = self.deviceModel()
        dict["device_localized_model"] = self.deviceLocalizedModel()
        dict["phone_identifier"] = self.phoneIdentifier()
        dict["app_identifier"] = self.appIdentifier()
        dict["screen_size"] = self.screenSize()
        dict["carrier"] = self.carrier()
        dict["network_type"] = self.networkType()
        return dict
    }
}
