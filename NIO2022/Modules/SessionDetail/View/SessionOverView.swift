//
//  SessionOverView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/18.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import SnapKit

class SessionOverView: UIView {
    var details:[[String:String]]
    
    var titleLabel:UILabel
    var contentView:HighlightView

    var titleHeight:CGFloat = 30
    
    init(title:String,details:[[String:String]]) {
        
        self.details = details
        
        let attrStr = title.addAttributes(.font(Font16), .color(ColorA))
        
        titleLabel = UILabel()
        titleLabel.numberOfLines = 1
        titleLabel.attributedText = attrStr
        
        contentView = HighlightView()
        contentView.backgroundColor = .white
        contentView.isUserInteractionEnabled = true
        //        contentView.addSubview(contentLabel)
        
        super.init(frame: CGRect.zero)
        addSubview(titleLabel)
        addSubview(contentView)
        addSubviews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addSubviews(){
        let stackView = UIStackView()
        stackView.axis = .vertical
        contentView.addSubview(stackView)
        
        var index = 0
        var lastV:UIView?
        for i in details {
            let itemView = BodyItemView(key: i.keys.first!, value: i.values.first ?? "", showArrow: false, isLast: index == details.count-1)
            index = index + 1
            stackView.addArrangedSubview(itemView)
            lastV = itemView
        }
        
        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(titleHeight)
            m.right.equalToSuperview()
        }
        stackView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalToSuperview()
            make.right.equalToSuperview()
            if lastV != nil {
                make.bottom.equalTo(lastV!.snp_bottom)
            }
        }
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.right.equalToSuperview()
            m.bottom.equalTo(stackView.snp_bottom)
        }
        snp.makeConstraints { make in
            make.bottom.equalTo(contentView.snp_bottom)
        }
    }
}
