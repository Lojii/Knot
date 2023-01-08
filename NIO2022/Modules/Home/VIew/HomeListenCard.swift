//
//  HomeListenCard.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/16.
//

import UIKit
import SnapKit

class HomeListenCard: HomeCard {

    var titleLabel:UILabel!
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI() -> Void {
        
        titleLabel = UILabel()
        titleLabel.font = Font18
        titleLabel.textColor = ColorB
        titleLabel.numberOfLines = 0
        titleLabel.text = ""
        addSubview(titleLabel)
        
        titleLabel.snp.makeConstraints { (m) in
            m.left.equalTo(snp.left).offset(HomeCard.LRMargin)
            m.right.equalTo(snp.right).offset(-HomeCard.LRMargin)
            m.top.equalTo(snp.top).offset(HomeCard.TBMargin)
        }

        snp.makeConstraints { make in
            make.width.equalTo(HomeCard.CardWidth)
            make.bottom.equalTo(titleLabel.snp_bottom).offset(HomeCard.TBMargin)
        }
    }

}
