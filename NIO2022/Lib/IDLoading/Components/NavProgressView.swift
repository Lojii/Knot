//
//  NavProgressView.swift
//  IDLoading
//
//  Created by darren on 2018/11/23.
//  Copyright © 2018年 陈亮陈亮. All rights reserved.
//

import UIKit
class NavProgressView: UIView {
    lazy var gradientLayer: CAGradientLayer = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = self.bounds
        gradientLayer.colors = [RGBAColor(13, 122, 255, 0.1).cgColor, RGBAColor(13, 122, 255, 0.5).cgColor, RGBAColor(13, 122, 255, 1).cgColor]
        gradientLayer.startPoint = CGPoint.init(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint.init(x: 1, y: 0.5)
        return gradientLayer
    }()
    
    var colors: [CGColor] = [RGBAColor(13, 122, 255, 0.1).cgColor, RGBAColor(13, 122, 255, 0.5).cgColor, RGBAColor(13, 122, 255, 1).cgColor] {
        didSet {
            self.gradientLayer.colors = colors
        }
    }
    
    var progress: CGFloat = 0 {
        didSet {
            let value = self.frame.width * progress
            
            self.gradientLayer.frame = CGRect.init(x: 0, y: 0, width: value, height: self.frame.height)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.layer.addSublayer(self.gradientLayer)
        
        if let rgbArr = IDealistConfig.share.mainColor.convertRGB() {
            print(rgbArr)
            let r = rgbArr.first ?? 13
            let g = rgbArr[1]
            let b = rgbArr.last ?? 255
            gradientLayer.colors = [RGBAColor(CGFloat(r), CGFloat(g), CGFloat(b), 0.1).cgColor, RGBAColor(CGFloat(r), CGFloat(g), CGFloat(b), 0.5).cgColor, RGBAColor(CGFloat(r), CGFloat(g), CGFloat(b), 1).cgColor]
        } else {
            print("conversion failed")
            gradientLayer.colors = [RGBAColor(13, 122, 255, 0.1).cgColor, RGBAColor(13, 122, 255, 0.5).cgColor, RGBAColor(13, 122, 255, 1).cgColor]
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
    }
}
