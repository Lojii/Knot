//
//  OtherItem.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/10.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

public class OtherItem: RuleLine {
    
    init(_ line:String) {
        super.init()
        self.line = line
        self.lineType = .Other
    }
    
    static func == (lhs: OtherItem, rhs: OtherItem) -> Bool {
        return lhs._line == rhs._line
    }
    
    override func lineDidSet() {
        
    }
    
    override func lineWillGet() {
        
    }
    
}
