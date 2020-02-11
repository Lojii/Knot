//
//  SessionItemView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class SessionItemView: UIView {
    
    var didClickHandle:((String) -> Void)?
    var content:String = ""
    
    var titleLabel:UILabel
    var contentView:HighlightView
    var contentLabel:UILabel
    var titleHeight:CGFloat = 30
    var contentHeight:CGFloat = 0
    var itemHeight:CGFloat = 0
    var isHeader:Bool
    var title:String

    init(title:String,content:String, _ isHeader:Bool = false) {
        self.isHeader = isHeader
        self.title = title
        self.content = content
        titleLabel = UILabel()
        titleLabel.textColor = ColorA
        titleLabel.font = Font16
        titleLabel.text = title
        
        contentLabel = UILabel()
        contentLabel.text = content
        contentLabel.numberOfLines = 0
        contentLabel.textColor = ColorB
        contentLabel.font = Font14
        contentLabel.lineBreakMode = .byCharWrapping
        contentLabel.textAlignment = .left
//        contentLabel.sizeToFit()
        // contentLabel.frame.height + 10//
        contentHeight = content.textHeight(font: contentLabel.font, fixedWidth: SCREENWIDTH - LRSpacing * 2) + 10
        
        contentView = HighlightView()
        contentView.backgroundColor = .white
        contentView.isUserInteractionEnabled = true
        contentView.addSubview(contentLabel)

        super.init(frame: CGRect.zero)
        addSubview(titleLabel)
        addSubview(contentView)
        setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI(){
        
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didClick)))
//        print("\(contentHeight)")
        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(titleHeight)
        }
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.right.equalToSuperview()
            m.height.equalTo(contentHeight)
        }
        contentLabel.snp.makeConstraints { (m) in
            m.top.equalToSuperview().offset(5)
//            m.bottom.equalToSuperview().offset(-5)
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing)
        }
        itemHeight = contentHeight + titleHeight + LRSpacing
    }
    
    @objc func didClick(){
        if let handle = didClickHandle {
            if isHeader {
                handle("\(title): \(content)")
            }else {
                handle(content)
            }
            
        }
    }
    
}
