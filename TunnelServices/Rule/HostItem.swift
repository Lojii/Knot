//
//  HostItem.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

public class HostItem: RuleLine {
    
    init(_ line:String) {
        super.init()
        self.lineType = .Host
    }
    
    static func == (lhs: HostItem, rhs: HostItem) -> Bool {
        return lhs._line == rhs._line
    }
    
    override func lineDidSet() {
        
    }
    
    override func lineWillGet() {
        
    }
    
    public static func fromLine(_ line:String, success:((RuleItem) -> Void), failure:((String?) -> Void) ) -> Void {
        
    }

}
