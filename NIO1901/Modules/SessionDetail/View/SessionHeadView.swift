//
//  SessionHeadView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/15.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionHeadView: UIView {

    var heads:[String:String]
    var didClickHandle:(() -> Void)?
    var titleLabel:UILabel
    var contentView:HighlightView
//    var contentLabel:UILabel
    var titleHeight:CGFloat = 30
    var contentHeight:CGFloat = 100
    var itemHeight:CGFloat = 0
    
    init(title:String,headJson:String) {
        
        heads = [String:String].fromJson(headJson)
        
        titleLabel = UILabel()
        titleLabel.textColor = ColorA
        titleLabel.font = Font16
        titleLabel.text = title
        
//        contentHeight = content.textHeight(font: contentLabel.font, fixedWidth: SCREENWIDTH - LRSpacing * 2) + 10
        
        contentView = HighlightView()
        contentView.backgroundColor = .white
        
//        contentView.isUserInteractionEnabled = true
        
        super.init(frame: CGRect.zero)
        addSubview(titleLabel)
        addSubview(contentView)
        setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func didClick(){
        if let handle = didClickHandle {
            handle()
        }
    }
    
    func setUI(){
        contentView.addTarget(self, action: #selector(didClick), for: .touchUpInside)
        var offY:CGFloat = 5
        var singular = false
        let keys = heads.keys.sorted { (k1, k2) -> Bool in
            return k1.localizedCompare(k2) == ComparisonResult.orderedAscending
        }
        for k in keys {
            let hLabel = HeadItemView(key: k, value: heads[k] ?? "", frame: CGRect(x: 0, y: offY, width: SCREENWIDTH, height: 30))
            hLabel.isUserInteractionEnabled = false
            hLabel.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: hLabel.height)
            singular = !singular
            offY = offY + hLabel.vheight
            contentView.addSubview(hLabel)
        }
        contentHeight = offY + 5
        
        let arrow = UIImageView(image: UIImage(named: "arrowright"))
        contentView.addSubview(arrow)
        arrow.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.right.equalToSuperview().offset(-5)
            m.width.height.equalTo(20)
        }
        
        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(titleHeight)
        }
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.right.equalToSuperview()
            m.height.equalTo(contentHeight)
        }
        itemHeight = contentHeight + titleHeight + LRSpacing
    }

}


class HeadItemView: UIView {
    
    var key:String
    var value:String
    
    var vheight:CGFloat = 0
    
    var itemLabel:UILabel

    init(key:String,value:String,frame:CGRect) {
        self.key = key
        self.value = value
        itemLabel = UILabel(frame: CGRect(x: LRSpacing, y: 0, width: frame.width - LRSpacing * 2 - 20, height: 100))
        itemLabel.numberOfLines = 0
        super.init(frame: frame)
        setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI(){
        addSubview(itemLabel)
        itemLabel.lineBreakMode = .byCharWrapping
        let attrStr = "\(key):".addAttributes(.font(Font14), .color(ColorA))
        if value != "" {
            attrStr.append(value.addAttributes(.font(Font14), .color(ColorB)))
        }
        itemLabel.attributedText = attrStr
        itemLabel.sizeToFit()
        vheight = itemLabel.frame.height
        let lineView = UIView()
        lineView.backgroundColor = ColorF
        addSubview(lineView)
        lineView.frame = CGRect(x: LRSpacing, y: height, width: frame.width - LRSpacing - 20, height: 1)
    }
}
