//
//  SessionOverView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/18.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionOverView: UIView {
    var details:[[String:String]]
    
    var titleLabel:UILabel
    var contentView:HighlightView
    //    var contentLabel:UILabel
    var titleHeight:CGFloat = 30
    var contentHeight:CGFloat = 0
    var itemHeight:CGFloat = 0
    var subItemHeight:CGFloat = 30
    
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
        setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addSubviews(){
        var offY:CGFloat = 0
        var index = 0
        for i in details {
            let itemView = BodyItemView(key: i.keys.first!, value: i.values.first ?? "", showArrow: false, isLast: index == details.count-1)
            index = index + 1
            itemView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: subItemHeight)
            offY = offY + subItemHeight
            contentView.addSubview(itemView)
        }
        contentHeight = offY
    }
    
    func setUI(){
        
        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(titleHeight)
            m.right.equalToSuperview()
        }
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.right.equalToSuperview()
            m.height.equalTo(contentHeight)
        }
        itemHeight = contentHeight + titleHeight + LRSpacing
    }
}
