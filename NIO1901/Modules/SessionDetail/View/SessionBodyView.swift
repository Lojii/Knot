//
//  SessionBodyView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/15.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class SessionBodyView: UIView {

    var path:String
    var type:String
    var size:CGFloat
    
    var titleLabel:UILabel
    var contentView:HighlightView
//    var contentLabel:UILabel
    var titleHeight:CGFloat = 30
    var contentHeight:CGFloat = 0
    var itemHeight:CGFloat = 0
    var subItemHeight:CGFloat = 30
    
    init(title:String,path:String,type:String,size:CGFloat) {
        
        self.path = path
        self.type = type
        self.size = size
        
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
        
        let preViewWidth:CGFloat = 100
        let preViewHeight:CGFloat = 100
        var offX:CGFloat = LRSpacing
        var offY:CGFloat = LRSpacing
        let preView = BodyPreView.getPreView(type, filePath: path)
        preView.frame = CGRect(x: offX, y: offY, width: preViewWidth, height: preViewHeight)
        contentView.addSubview(preView)
        offX = offX + preViewWidth
        
        contentHeight = LRSpacing + preView.frame.height + LRSpacing
        offY = offY - 5
        var index = 0
        for i in preView.infos {
            let itemView = BodyItemView(key: i.keys.first!, value: i.values.first ?? "", showArrow: false, isLast: index == preView.infos.count-1)
            index = index + 1
            itemView.frame = CGRect(x: offX, y: offY, width: SCREENWIDTH - offX, height: subItemHeight)
            offY = offY + subItemHeight
            contentView.addSubview(itemView)
        }
        contentHeight = CGFloat.maximum(preViewHeight + LRSpacing, offY) + LRSpacing
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

class BodyItemView:UIView{
    var key:String
    var value:String
    var showArrow = false
    var isLast = false
    
    var keyLabel:UILabel
    var valueLabel:UILabel
    var arrowView:UIImageView
    var lineView:UIView
    
//    var height:CGFloat = 0
    
    
    init(key:String,value:String,showArrow:Bool = false,isLast:Bool = false) {
        self.key = key
        self.value = value
        self.showArrow = showArrow
        self.isLast = isLast
        keyLabel = UILabel.initWith(color: ColorA, font: Font14, text: key, frame: CGRect.zero)
        keyLabel.numberOfLines = 0
        valueLabel = UILabel.initWith(color: ColorA, font: Font14, text: value, frame: CGRect.zero)
        valueLabel.numberOfLines = 0
        arrowView = UIImageView(image: UIImage(named: "arrowright"))
        arrowView.isHidden = !showArrow
        lineView = UIView()
        lineView.backgroundColor = ColorF
        lineView.isHidden = isLast
        super.init(frame: CGRect.zero)
        setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI(){
        addSubview(keyLabel)
        addSubview(valueLabel)
        addSubview(arrowView)
        addSubview(lineView)
        arrowView.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.width.height.equalTo(13)
            m.right.equalToSuperview().offset(-LRSpacing)
        }
        valueLabel.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.right.equalToSuperview().offset(-LRSpacing-(showArrow ? 13 : 0))
            m.height.equalToSuperview()
        }
        keyLabel.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.left.equalToSuperview().offset(LRSpacing)
            m.height.equalToSuperview()
            m.right.equalTo(valueLabel.snp.left)
        }
        lineView.snp.makeConstraints { (m) in
            m.bottom.equalToSuperview()
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing)
            m.height.equalTo(1)
        }
    }
}
