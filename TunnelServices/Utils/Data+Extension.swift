//
//  Data+Extension.swift
//  TunnelServices
//
//  Created by LiuJie on 2019/5/10.
//  Copyright © 2019 Lojii. All rights reserved.
//

import Foundation

extension Data{
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        }
        else {
            try write(to: fileURL, options: .atomic)
        }
    }
}
