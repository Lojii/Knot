//
//  HomeCard.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/16.
//

import UIKit
import SnapKit

class HomeCard: UIView {
    
    static let LRMargin:CGFloat = 15
    static let TBMargin:CGFloat = 14
    static let CardWidth:CGFloat = SCREENWIDTH - 30

    override init(frame: CGRect) {
        super.init(frame: frame)
        setBaseUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setBaseUI(){
        backgroundColor = .white
        layer.cornerRadius = 10
    }
    
}
