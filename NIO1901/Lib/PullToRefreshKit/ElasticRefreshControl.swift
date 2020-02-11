//
//  ElasticRefreshControl.swift
//  SWTest
//
//  Created by huangwenchen on 16/7/29.
//  Copyright © 2016年 Leo. All rights reserved.
//

import Foundation
import UIKit

@IBDesignable
open class ElasticRefreshControl: UIView {
    //目标，height 80, 高度 40
    public let spinner: UIActivityIndicatorView = UIActivityIndicatorView()
    var radius: CGFloat{
        get{
            return totalHeight / 4 - margin
        }
    }
    open var progress: CGFloat = 0.0{
        didSet{
            setNeedsDisplay()
        }
    }
    open var margin: CGFloat = 4.0{
        didSet{
            setNeedsDisplay()
        }
    }
    var arrowRadius: CGFloat{
        get{
            return radius * 0.5 - 0.2 * radius * adjustedProgress
        }
    }
    var adjustedProgress: CGFloat{
        get{
            return min(max(progress,0.0),1.0)
        }
    }
    let totalHeight: CGFloat = 80
    open var arrowColor = UIColor.white{
        didSet{
            setNeedsDisplay()
        }
    }
    open var elasticTintColor = UIColor.init(white: 0.5, alpha: 0.6){
        didSet{
            setNeedsDisplay()
        }
    }
    var animating = false{
        didSet{
            if animating{
                spinner.startAnimating()
                setNeedsDisplay()
            }else{
                spinner.stopAnimating()
                setNeedsDisplay()
            }
        }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    func commonInit(){
        self.isOpaque = false
        addSubview(spinner)
        sizeToFit()
        spinner.hidesWhenStopped = true
        #if swift(>=4.2)
        spinner.style = .gray
        #else
        spinner.activityIndicatorViewStyle = .gray
        #endif
    }
   open override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: self.bounds.width / 2.0, y: 0.75 * totalHeight)
    }
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    func sinCGFloat(_ angle:CGFloat)->CGFloat{
        let result = sinf(Float(angle))
        return CGFloat(result)
    }
    func cosCGFloat(_ angle:CGFloat)->CGFloat{
        let result = cosf(Float(angle))
        return CGFloat(result)
    }
    open override func draw(_ rect: CGRect) {
        if animating {
            super.draw(rect)
            return
        }
        let context = UIGraphicsGetCurrentContext()
        let centerX = rect.width/2.0
        let lineWidth = 2.5 - 1.0 * adjustedProgress
        let upCenter = CGPoint(x: centerX, y: (0.75 - 0.5 * adjustedProgress) * totalHeight)
        let upRadius = radius - radius * 0.3 * adjustedProgress
        let downRadius:CGFloat = radius  - radius * 0.75 * adjustedProgress
        let downCenter = CGPoint(x: centerX, y: totalHeight - downRadius - margin)
        let offSetAngle:CGFloat = CGFloat.pi / 2.0 / 12.0
        let upP1 = CGPoint(x: upCenter.x - upRadius * cosCGFloat(offSetAngle), y: upCenter.y + upRadius * sinCGFloat(offSetAngle))
        let upP2 = CGPoint(x: upCenter.x + upRadius * cosCGFloat(offSetAngle), y: upCenter.y + upRadius * sinCGFloat(offSetAngle))
        let downP1 = CGPoint(x: downCenter.x - downRadius * cosCGFloat(offSetAngle), y: downCenter.y -  downRadius * sinCGFloat(offSetAngle))
        let controPonintLeft = CGPoint(x: downCenter.x - downRadius, y: (downCenter.y + upCenter.y)/2)
        let controPonintRight = CGPoint(x: downCenter.x + downRadius, y: (downCenter.y + upCenter.y)/2)
        context?.setFillColor(elasticTintColor.cgColor)
        context?.addArc(center: upCenter, radius: upRadius, startAngle: -CGFloat.pi - offSetAngle, endAngle: offSetAngle, clockwise: false)
        context?.move(to: CGPoint(x: upP1.x, y: upP1.y))
        context?.addQuadCurve(to: downP1, control: controPonintLeft)
        context?.addArc(center: downCenter, radius: downRadius, startAngle: -CGFloat.pi - offSetAngle, endAngle: offSetAngle, clockwise: true)
        context?.addQuadCurve(to: upP2, control: controPonintRight)
        context?.fillPath()
        context?.setStrokeColor(arrowColor.cgColor)
        context?.setLineWidth(lineWidth)
        context?.addArc(center: upCenter, radius: arrowRadius, startAngle: 0, endAngle: CGFloat.pi * 1.5, clockwise: false)
        context?.strokePath()
        
        context?.setFillColor(arrowColor.cgColor)
        context?.setLineWidth(0.0)
        
        context?.move(to: CGPoint(x: upCenter.x, y: upCenter.y - arrowRadius - lineWidth * 1.5))
        context?.addLine(to: CGPoint(x: upCenter.x, y: upCenter.y - arrowRadius + lineWidth * 1.5))
        context?.addLine(to: CGPoint(x: upCenter.x + lineWidth * 0.865 * 3, y: upCenter.y - arrowRadius))
        context?.addLine(to: CGPoint(x: upCenter.x, y: upCenter.y - arrowRadius - lineWidth * 1.5))
        context?.fillPath()
        
    }
    override open func sizeToFit() {
        var width = frame.size.width
        if width < 30.0{
            width = 30.0
        }
        self.frame = CGRect(x: frame.origin.x, y: frame.origin.y,width: width, height: totalHeight)
    }
}
