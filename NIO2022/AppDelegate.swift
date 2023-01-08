//
//  AppDelegate.swift
//  NIO2022
//
//  Created by LiuJie on 2022/3/2.
//

import UIKit
import ActiveSQLite
import NIOMan
import Bugly

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var backgroundTask:UIBackgroundTaskIdentifier?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        Bugly.start(withAppId: "02c6f56773")
        // 在group里创建数据库
        ASConfigration.setDefaultDB(path: NIOMan.DBPath(), name: DBDefaultName )
        ASConfigration.logLevel = .error
        NIOMan.DatabaseInit("Default".localized)
        // 将证书移入group
        // crt
        
        let fileManager = FileManager.default
        // 设置
        if let httpRootDir = NIOMan.CertPath() {
            // 判断本地是否有证书，如果没有则创建
            let certPath = httpRootDir.appendingPathComponent("CA.cert.pem")
            let keyPath = httpRootDir.appendingPathComponent("CA.key.pem")
            if !fileManager.fileExists(url: certPath) || !fileManager.fileExists(url: keyPath) {
                if !NIOMan.CAGenerate(httpRootDir.path.components(separatedBy: "file://").last!) {
                    print("首次启动，证书创建失败")
                }
            }
            let httpPath = httpRootDir.appendingPathComponent("index.html")
            if !fileManager.fileExists(url: httpPath) {
                if let bundleHttpPath = Bundle.main.url(forResource: "Http/index", withExtension: "html") {
                    try? fileManager.copyItem(at: bundleHttpPath, to: httpPath)
                }
            }
            // 移动默认忽略host列表
            let balcklistPath = httpRootDir.appendingPathComponent("blacklist")
            if let bundleBalcklistPath = Bundle.main.url(forResource: "Http/blacklist", withExtension: nil) {
                try? fileManager.copyItem(at: bundleBalcklistPath, to: balcklistPath)
            }
        }
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: HomeViewController())
//        window?.rootViewController = UINavigationController(rootViewController: ViewController())
//        window?.rootViewController = UINavigationController(rootViewController: HomeVC())
        
        window?.makeKeyAndVisible()
        // 内购
//        KnotPurchase.payFailed(.HappyKnot)
        KnotPurchase.initPurchase()
        
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        beginBackgroundTask()
    }

    func beginBackgroundTask(){
        print("后台任务启动")
        backgroundTask = UIApplication.shared.beginBackgroundTask()
        DispatchQueue.global().async {
            sleep(29)
            self.endBackGroundTask()
        }
    }
    
    func endBackGroundTask(){
        print("后台任务退出")
        UIApplication.shared.endBackgroundTask(backgroundTask!)
        backgroundTask = .invalid
    }
    
}

