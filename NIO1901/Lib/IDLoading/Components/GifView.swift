//
//  GifView.swift
//  Loadding
//
//  Created by darren on 2017/11/27.
//  Copyright © 2017年 陈亮陈亮. All rights reserved.
//

import UIKit
import ImageIO
import QuartzCore

typealias completionBlock = ()->()  // 动画完成后做的事情
class GifView: UIView, CAAnimationDelegate {

    private var gifurl: URL! = BundleUtil.getCurrentBundle().url(forResource: "Lodging", withExtension: "gif") // 把本地图片转化成URL
    private var imageArr: Array<CGImage> = [] // 图片数组（存放每一帧的图片）
    private var timeArr: Array<NSNumber> = [] // 时间数组 (存放每一帧的图片的时间)
    private var totalTime: Float = 0 // gif 动画时间
    private var completionClosure: completionBlock?
    
    /**
     *  加载本地GIF 图片
     */
    func showGIFImageWithLocalName(gifUrl: URL, completionClosure:@escaping (()->())) {
        self.completionClosure = completionClosure
        self.gifurl = gifUrl
        self.createKeyFram()
    }
    func showGIFImageWithLocalName(completionClosure:@escaping (()->())) {
        self.completionClosure = completionClosure
        self.createKeyFram()
    }
    
    /**
     *  获取GIF 图片的每一帧有关的东西 比如：每一帧的图片、每一帧图片执行的时间
     */
    private func createKeyFram() {
        let url: CFURL = self.gifurl as CFURL
        let gifSource = CGImageSourceCreateWithURL(url, nil)
        let imageCount = CGImageSourceGetCount(gifSource!) // 总共图片张数
        
        for i in 0..<imageCount {
            let imageRef = CGImageSourceCreateImageAtIndex(gifSource!, i, nil) // 取得每一帧的图
            self.imageArr.append(imageRef!)
            
            let sourceDict = CGImageSourceCopyPropertiesAtIndex(gifSource!, i, nil) as NSDictionary?
            let gifDict = sourceDict![String(kCGImagePropertyGIFDictionary)] as! NSDictionary?
            let time = gifDict![String(kCGImagePropertyGIFUnclampedDelayTime)] as! NSNumber // 每一帧的动画时间
            self.timeArr.append(time)
            self.totalTime += time.floatValue
            
            // 获取图片的尺寸 (适应)
            let imageWidth = sourceDict![String(kCGImagePropertyPixelWidth)] as! NSNumber
            let imageHeight = sourceDict![String(kCGImagePropertyPixelHeight)] as! NSNumber
            
            if (imageWidth.floatValue / imageHeight.floatValue) != Float(self.frame.size.width/self.frame.size.height) {
                self.fitScale(imageWidth: CGFloat(imageWidth.floatValue), imageHeight: CGFloat(imageHeight.floatValue))
            }
        }
        
        self.showAnimation()
    }
    
    /**
     *  适应
     */
    private func fitScale(imageWidth: CGFloat, imageHeight: CGFloat) {
        var newWidth: CGFloat
        var newHeight: CGFloat
        if imageWidth/imageHeight > self.bounds.width/self.bounds.height {
            newWidth = self.bounds.width
            newHeight = self.frame.size.width/(imageWidth/imageHeight)
        } else {
            newHeight = self.frame.size.height
            newWidth = self.frame.size.height/(imageHeight/imageWidth)
        }
        let point = self.center;
        
        self.frame.size = CGSize(width: newWidth, height: newHeight)
        self.center = point
    }
    
    /**
     *  展示动画
     */
    private func showAnimation() {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        var current: Float = 0
        var timeKeys: Array<NSNumber> = []
        
        for time in timeArr {
            timeKeys.append(NSNumber(value: current/self.totalTime))
            current += time.floatValue
        }
        
        animation.keyTimes = timeKeys
        animation.delegate = self
        animation.values = self.imageArr
        animation.repeatCount = MAXFLOAT
        animation.duration = TimeInterval(totalTime)
        animation.isRemovedOnCompletion = false
        self.layer.add(animation, forKey: "GifView")
    }
    
    func stopAnimation() {
        if self.completionClosure != nil {
            self.completionClosure!()
        }
    }
    
    // Delegate 动画结束
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if self.completionClosure != nil {
            self.completionClosure!()
        }
    }
}

