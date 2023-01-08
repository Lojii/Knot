//
//  HomeCertStatuCard.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/16.
//

import UIKit
import SnapKit

class HomeCertStatuCard: HomeListenCard {

    var didClick: (() -> Void)?
    
    var _status: TrustResultType = .trusted
    var status: TrustResultType {
        get { return _status }
        set {
            _status = newValue
            if _status == .none {
                titleLabel.text = "The certificate is not installed. Click Install".localized
                isHidden = false
            }
            if _status == .installed {
                titleLabel.text = "The current certificate is not trusted".localized
                isHidden = false
            }
            if _status == .trusted {
                titleLabel.text = "Trusted".localized
                isHidden = true
            }
        }
    }
    
    override init(frame: CGRect){
        super.init(frame: frame)
        backgroundColor = ColorY
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardDidClick)))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func cardDidClick() -> Void {
        didClick?()
    }
        
}
