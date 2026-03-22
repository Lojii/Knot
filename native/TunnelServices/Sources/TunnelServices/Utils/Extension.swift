//
//  Extension.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/6/16.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation

extension FileManager {
    public func fileExists(url:URL) -> Bool {
        let urlStr = url.absoluteString
        if let filePath = urlStr.components(separatedBy: "file://").last {
            return fileExists(atPath: filePath)
        }
        return false
    }
}
