//
//  ViewController.swift
//  AxLoggerDemo
//
//  Created by 孔祥波 on 18/11/2016.
//  Copyright © 2016 Kong XiangBo. All rights reserved.
//

import UIKit
import Foundation
import AxLogger
class ViewController: UIViewController {

    let  applicationDocumentsDirectory: URL = {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "com.yarshuremac.test" in the application's documents Application Support directory.
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[urls.count-1]
    }()

    override func viewDidLoad() {
        
        super.viewDidLoad()
        let ur  = self.applicationDocumentsDirectory.appendingPathComponent("abc")
        print(ur)
        AxLogger.openLogging(ur, date: Date(),debug: true)
        AxLogger.log("test", level: .Debug)
        AxLogger.log("test", level: .Info)
        print(ur,stdout)
        NSLog("lsskdjflsjdflaksdjflkas %") //stdout.log
        let leve = loglevel("trace")
        print(leve.description)
        
        
//        SFLogger.shared.openHandle(path: "/Users/yarshure/xx.txt")
//         SFLogger.logleve = .Debug
//        let env = AxEnvHelper.infoDict()
//        let data = "saldkfjskldfjdslfjklsadjfkladsj".data(using: .utf8)!
//        SFLogger.log("Env", items: env, level: .Info)
//        SFLogger.log("Env", items: data as NSData, level: .Info)
//        SFLogger.log("Test", items: ur, level: .Debug)
        // Do any additional setup after loading the view, typically from a nib.
    }

    func loglevel(_ levelStr:String) -> AxLoggerLevel {
        
        var level:AxLoggerLevel = .Info
        let l = levelStr.lowercased()
        
        switch l {
        case "error": level = .Error
        case "warning": level = .Warning
        case "info": level = .Info
        case "notify": level = .Notify
        case "trace": level = .Trace
        case "verbose": level = .Verbose
        case "debug": level = .Debug
        default:
            break
        }
        return level
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

