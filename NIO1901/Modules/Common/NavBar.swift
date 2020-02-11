//
//  NavBar.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class NavBar: UIView {

    public lazy var titleLable:UILabel = {
        let titleLable = UILabel()
        titleLable.textAlignment = .center
        titleLable.font = UIFont.boldSystemFont(ofSize: 18)
        return titleLable
    }()
    public lazy var navLine:UIView = {
        let navLine = UIView()
        navLine.backgroundColor = UIColor.groupTableViewBackground
        return navLine
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.addSubview(self.titleLable)
        self.addSubview(self.navLine)
        initEventHendle()
    }
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func initEventHendle() {
        self.titleLable.translatesAutoresizingMaskIntoConstraints = false
        self.navLine.translatesAutoresizingMaskIntoConstraints = false
        
        let titleY: CGFloat = UIDevice.isX() == true ? 40:20
        self.titleLable.addConstraint(NSLayoutConstraint.init(item: self.titleLable, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 44))
        self.addConstraints([
            NSLayoutConstraint.init(item: self.titleLable, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 50),
            NSLayoutConstraint.init(item: self.titleLable, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1, constant: titleY),
            NSLayoutConstraint.init(item: self.titleLable, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: -50)
            ])
        
        self.navLine.addConstraint(NSLayoutConstraint.init(item: self.navLine, attribute: NSLayoutConstraint.Attribute.height, relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil, attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 0, constant: 1))
        self.addConstraints([
            NSLayoutConstraint.init(item: self.navLine, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.navLine, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self, attribute: NSLayoutConstraint.Attribute.bottom, multiplier: 1, constant: 0),
            NSLayoutConstraint.init(item: self.navLine, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: self, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1, constant: 0)
            ])
    }
    override open func layoutSubviews() {
    }

}
