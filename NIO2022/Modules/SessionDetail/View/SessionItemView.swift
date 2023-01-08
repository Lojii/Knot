//
//  SessionItemView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import SnapKit

class SessionItemView: UIView {
    
    var didClickHandle:((String) -> Void)?
    var content:String = ""
    
    var titleLabel:UILabel
    var contentView:HighlightView
    var contentLabel:UILabel
//    var titleHeight:CGFloat = 30
//    var contentHeight:CGFloat = 0
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
//        contentHeight = content.finalSize(contentLabel.font, CGSize(width: SCREENWIDTH - LRSpacing * 2, height: 10000)).height
//        contentHeight = content.textHeight(font: contentLabel.font, fixedWidth: SCREENWIDTH - LRSpacing * 2) + 10
        
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
        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(30)
        }
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.equalTo(snp_left)
            m.right.equalTo(snp_right)
            m.bottom.equalTo(contentLabel.snp_bottom).offset(5)
        }
        contentLabel.snp.makeConstraints { (m) in
            m.top.equalTo(contentView.snp_top).offset(5)
            m.left.equalTo(contentView.snp_left).offset(LRSpacing)
            m.right.equalTo(contentView.snp_right).offset(-LRSpacing)
        }
        snp.makeConstraints { make in
            make.bottom.equalTo(contentView.snp_bottom)
            make.width.equalTo(SCREENWIDTH)
        }
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
