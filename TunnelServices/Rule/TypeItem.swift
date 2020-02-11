//
//  TYPEItem.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/10.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

//
public class TypeItem: RuleLine {
    
    var itemType:RuleType = .Other
    
    init(_ line:String) {
        super.init()
        self.line = line
        self.lineType = .Type
    }

    static func == (lhs: TypeItem, rhs: TypeItem) -> Bool {
        return lhs._line == rhs._line
    }
    
    override func lineDidSet() {
        if _line.lowercased().starts(with: "[general]"){
            itemType = .General
        }
        if _line.lowercased().starts(with: "[rule]") {
            itemType = .Rule
        }
        if _line.lowercased().starts(with: "[host]") {
            itemType = .Host
        }
    }
    
    override func lineWillGet() {
        
    }
}
