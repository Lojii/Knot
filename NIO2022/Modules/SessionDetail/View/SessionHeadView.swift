//
//  SessionHeadView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/15.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class SessionHeadView: UIView {

    var _heads:[String:String]
    var didClickHandle:(() -> Void)?
    var titleLabel:UILabel
    var contentView:HighlightView
    var titleHeight:CGFloat = 30
    
    init(title:String,heads:[String:String]) {
        
        _heads = heads
        
        titleLabel = UILabel()
        titleLabel.textColor = ColorA
        titleLabel.font = Font16
        titleLabel.text = title
        
        contentView = HighlightView()
        contentView.backgroundColor = .white
        
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

        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(titleHeight)
        }
        
        let leftView = NoRespondStackView()
        leftView.axis = .vertical
        contentView.addSubview(leftView)

        let arrow = UIImageView(image: UIImage(named: "arrowright"))
        contentView.addSubview(arrow)
        arrow.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.right.equalToSuperview().offset(-5)
            m.width.height.equalTo(20)
        }
        
        leftView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp_bottom)
            make.left.equalTo(contentView.snp_left)
            make.right.equalTo(contentView.snp_right)
        }
        var singular = false
        let keys = _heads.keys.sorted { (k1, k2) -> Bool in
            return k1.localizedCompare(k2) == ComparisonResult.orderedAscending
        }
        for k in keys {
            let hLabel = HeadItemView(key: k, value: _heads[k] ?? "")
            hLabel.isUserInteractionEnabled = false
//            if singular { hLabel.backgroundColor = ColorF }
            singular = !singular
            leftView.addArrangedSubview(hLabel)
        }
        
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.right.equalToSuperview()
            m.bottom.equalTo(leftView.snp_bottom)
        }
        
        snp.makeConstraints { make in
            make.bottom.equalTo(contentView.snp_bottom)
        }
    }

}

class NoRespondStackView:UIStackView {
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView == self {
            return nil
        }
        return hitView
    }
    
}

class HeadItemView: UIView {
    
    var key:String
    var value:String
    
//    var vheight:CGFloat = 0
    
    var itemLabel:UILabel

    init(key:String,value:String) {
        self.key = key
        self.value = value
        itemLabel = UILabel()
        super.init(frame: CGRect.zero)
        setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView == self {
            return nil
        }
        return hitView
    }
    
    func setUI(){
        itemLabel.numberOfLines = 0
        itemLabel.lineBreakMode = .byCharWrapping
        let attrStr = "\(key):".addAttributes(.font(Font14), .color(ColorA))
        if value != "" {
            attrStr.append(value.addAttributes(.font(Font14), .color(ColorB)))
        }
        itemLabel.attributedText = attrStr
        itemLabel.sizeToFit()
        
        addSubview(itemLabel)
        
        itemLabel.snp.makeConstraints { make in
            make.left.equalTo(snp_left).offset(LRSpacing)
            make.right.equalTo(snp_right).offset(-LRSpacing)
            make.top.equalTo(snp_top).offset(5)
        }
        
        
        let lineView = UIView()
        lineView.backgroundColor = ColorF
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(snp_left).offset(LRSpacing)
            make.right.equalTo(snp_right).offset(LRSpacing)
            make.bottom.equalTo(snp_bottom)
            make.height.equalTo(1)
        }
        
        snp.makeConstraints { make in
            make.bottom.equalTo(itemLabel.snp_bottom).offset(5)
        }
    }
}
