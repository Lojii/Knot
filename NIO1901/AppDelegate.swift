//
//  AppDelegate.swift
//  NIO1901
//
//  Created by Lojii on 2019/1/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import AVFoundation
import TunnelServices
import YYWebImage
import Bugly

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var backgroundTask:UIBackgroundTaskIdentifier?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        Bugly.start(withAppId: "0519d95ff6")
        Bugly.setUserValue("Main", forKey: "App")
        
        ASConfigration.setDefaultDB(path: MitmService.getDBPath(), name: "Session")
        ASConfigration.logLevel = .error
        // Default Rule
        if UserDefaults.standard.string(forKey: "first") == nil {
            Bugly.setUserValue("true", forKey: "IsFirst")
            let defaultRule = Rule.defaultRule()
            try? defaultRule.saveToDB()
            UserDefaults.standard.set("\(defaultRule.id ?? -1)", forKey: CurrentRuleId)
            UserDefaults.standard.set("no first", forKey: "first")
            UserDefaults.standard.synchronize()
        }
        let fileManager = FileManager.default
        if let certDir = MitmService.getCertPath() {
            // Cert
            let cacertPath = certDir.appendingPathComponent("cacert.pem", isDirectory: false)
            let cacertDerPath = certDir.appendingPathComponent("cacert.der", isDirectory: false)
            let cakeyPath = certDir.appendingPathComponent("cakey.pem", isDirectory: false)
            let rsakeyPath = certDir.appendingPathComponent("rsakey.pem", isDirectory: false)
//            let cc = try? String(contentsOf: cacertPath)
            if !fileManager.fileExists(url: cacertPath) {
                let fullCC = cc1 + cc2 + cc3
                try? fullCC.write(to: cacertPath, atomically: true, encoding: .utf8)
            }
            if !fileManager.fileExists(url: cacertDerPath) {
                let derData = Data(base64Encoded: ccDerBase64)
                try? derData?.write(to: cacertDerPath, options: Data.WritingOptions.atomic)
            }
            if !fileManager.fileExists(url: cakeyPath) {
                let fullck = ck1 + ck2 + ck3
                try? fullck.write(to: cakeyPath, atomically: true, encoding: .utf8)
            }
            if !fileManager.fileExists(url: rsakeyPath) {
                let fullrk = rk1 + rk2 + rk3
                try? fullrk.write(to: rsakeyPath, atomically: true, encoding: .utf8)
            }
            // DefaultBlackLisk
            let blackListPath = certDir.appendingPathComponent("DefaultBlackLisk.conf", isDirectory: false)
            if !fileManager.fileExists(url: blackListPath) {
                if let bundleBlackListPath = Bundle.main.url(forResource: "CA/DefaultBlackLisk", withExtension: "conf") {
                    try? fileManager.copyItem(at: bundleBlackListPath, to: blackListPath)
                }
            }
        }
        if let httpRootDir = LocalHTTPServer.httpRootPath {
            if fileManager.fileExists(url: httpRootDir) {
                let httpPath = httpRootDir.appendingPathComponent("index.html")
                if !fileManager.fileExists(url: httpPath) {
                    if let bundleHttpPath = Bundle.main.url(forResource: "Http/index", withExtension: "html") {
                        try? fileManager.copyItem(at: bundleHttpPath, to: httpRootDir.appendingPathComponent("index.html"))
                    }
                }
                let cacertPath = httpRootDir.appendingPathComponent("cacert.pem", isDirectory: false)
                if !fileManager.fileExists(url: cacertPath) {
                    let fullCC = cc1 + cc2 + cc3
                    let ccData = fullCC.data(using: .utf8)
                    try! ccData?.write(to: cacertPath, options: Data.WritingOptions.atomic)
                }
            }else{
                do{
                    try fileManager.createDirectory(at: httpRootDir, withIntermediateDirectories: false, attributes: nil)
                    
                    let httpPath = httpRootDir.appendingPathComponent("index.html")
                    if !fileManager.fileExists(url: httpPath) {
                        if let bundleHttpPath = Bundle.main.url(forResource: "Http/index", withExtension: "html") {
                            try? fileManager.copyItem(at: bundleHttpPath, to: httpRootDir.appendingPathComponent("index.html"))
                        }
                    }
                    let cacertPath = httpRootDir.appendingPathComponent("cacert.pem", isDirectory: false)
                    if !fileManager.fileExists(url: cacertPath) {
                        let fullCC = cc1 + cc2 + cc3
                        let ccData = fullCC.data(using: .utf8)
                        try! ccData?.write(to: cacertPath, options: Data.WritingOptions.atomic)
                    }
                }catch{
                    print("HttpRootDir Setting Failure ! \(error.localizedDescription)")
                }
                
            }
        }
        
//        LocationStepsManager.shared.availableLocationService()
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: MainViewController())

        window?.makeKeyAndVisible()
        
        if let cache = YYWebImageManager.shared().cache {
            cache.diskCache.removeAllObjects()
        }
        
        return true
    }
    
    
//    beginBackgroundTaskWithExpirationHandler
    func applicationDidEnterBackground(_ application: UIApplication) {
        beginBackgroundTask()
        
//        endBackGroundTask()
    }

    func beginBackgroundTask(){
        print("后台任务启动")
        backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            DispatchQueue.global().async {
                sleep(60)
                self.endBackGroundTask()
            }
        })
    }
    
    func endBackGroundTask(){
        print("后台任务退出")
        UIApplication.shared.endBackgroundTask(backgroundTask!)
        backgroundTask = .invalid
    }
    
}

