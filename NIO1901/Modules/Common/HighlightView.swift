//
//  HighlightView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/5.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class HighlightView: UIButton {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setBackgroundImage(UIImage.renderImageWithColor(ColorE, size: CGSize(width: 1, height: 1)), for: .highlighted)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
