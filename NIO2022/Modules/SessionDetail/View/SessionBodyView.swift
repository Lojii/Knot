//
//  SessionBodyView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/15.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import SnapKit

class SessionBodyView: UIView {

    var path:String
    var type:String
    var size:CGFloat
    
    var titleLabel:UILabel
    var contentView:HighlightView
    
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
        
        super.init(frame: CGRect.zero)
        addSubview(titleLabel)
        addSubview(contentView)
        addSubviews()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addSubviews(){
        
        let preViewWH:CGFloat = 100
        let preView = BodyPreView.getPreView(type, filePath: path)
        contentView.addSubview(preView)
        contentView.isUserInteractionEnabled = false
        preView.snp.makeConstraints { make in
            make.width.height.equalTo(preViewWH)
            make.left.equalTo(contentView.snp_left).offset(LRSpacing)
            make.top.equalTo(contentView.snp_top).offset(LRSpacing)
        }
        
        let rightView = UIStackView()
        rightView.axis = .vertical
        contentView.addSubview(rightView)
        var index = 0
        var lastView:UIView?
        for i in preView.infos {
            let itemView = BodyItemView(key: i.keys.first!, value: i.values.first ?? "", showArrow: false, isLast: index == preView.infos.count-1)
            index = index + 1
            rightView.addArrangedSubview(itemView)
            lastView = itemView
        }
        rightView.snp.makeConstraints { make in
            make.top.equalTo(contentView.snp_top).offset(10)
            make.left.equalTo(preView.snp_right).offset(5)
            make.right.equalTo(contentView.snp_right)
            if(lastView != nil){
                make.bottom.equalTo(lastView!.snp_bottom)
            }
        }
        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(30)
            m.right.equalToSuperview()
        }
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.right.equalToSuperview()
            m.bottom.greaterThanOrEqualTo(rightView.snp_bottom).offset(LRSpacing - 5)
            m.bottom.greaterThanOrEqualTo(preView.snp_bottom).offset(LRSpacing)
        }
        snp.makeConstraints { make in
            make.bottom.equalTo(contentView.snp_bottom)
        }
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
    
    init(key:String,value:String,showArrow:Bool = false,isLast:Bool = false) {
        self.key = key
        self.value = value
        self.showArrow = showArrow
        self.isLast = isLast
        keyLabel = UILabel.initWith(color: ColorA, font: Font14, text: key, frame: CGRect.zero)
        keyLabel.numberOfLines = 0
        valueLabel = UILabel.initWith(color: ColorA, font: Font14, text: value, frame: CGRect.zero)
        valueLabel.numberOfLines = 0
        valueLabel.textAlignment = .right
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
        keyLabel.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing)
            m.top.equalTo(snp_top).offset(5)
        }
        keyLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        valueLabel.snp.makeConstraints { (m) in
            m.top.equalTo(keyLabel.snp_top)
            m.left.equalTo(keyLabel.snp_right).offset(5)
            m.right.equalToSuperview().offset(-LRSpacing-(showArrow ? 13 : 0))
        }
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        arrowView.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.width.height.equalTo(13)
            m.right.equalToSuperview().offset(-LRSpacing)
        }
        snp.makeConstraints { m in
            m.bottom.greaterThanOrEqualTo(keyLabel.snp_bottom).offset(5)
            m.bottom.greaterThanOrEqualTo(valueLabel.snp_bottom).offset(5)
        }
        lineView.snp.makeConstraints { (m) in
            m.bottom.equalToSuperview()
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing)
            m.height.equalTo(1)
        }
    }
}
