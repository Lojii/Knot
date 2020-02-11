//
//  UIImageView+ImageViewer.swift
//  ImageViewer
//
//  Created by Tan Nghia La on 03.05.15.
//  Copyright (c) 2015 Tan Nghia La. All rights reserved.
//

import Foundation
import UIKit

public extension UIImageView {
    
    func setupForImageViewer(_ backgroundColor: UIColor = UIColor.white) {
        isUserInteractionEnabled = true
        let gestureRecognizer = ImageViewerTapGestureRecognizer(target: self, action: #selector(didTap(_:)), backgroundColor: backgroundColor)
        addGestureRecognizer(gestureRecognizer)
    }
    
    @objc internal func didTap(_ recognizer: ImageViewerTapGestureRecognizer) {
        let imageViewer = ImageViewer(senderView: self, backgroundColor: recognizer.backgroundColor)
        imageViewer.presentFromRootViewController()
    }
}

class ImageViewerTapGestureRecognizer: UITapGestureRecognizer {
    let backgroundColor: UIColor
    
    init(target: AnyObject, action: Selector, backgroundColor: UIColor) {
        self.backgroundColor = backgroundColor
        
        super.init(target: target, action: action)
    }
}
