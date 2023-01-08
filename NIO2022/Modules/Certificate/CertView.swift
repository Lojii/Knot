//
//  CertView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/22.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

protocol CertViewDelegate: class {
    func certViewBtnDidClick(status:TrustResultType)
    func certViewCertDidClick()
}

class CertView: UIView {

    @IBOutlet weak var installBtn: UIButton!
    @IBOutlet weak var certContentView: UIView!
    @IBOutlet weak var certIconView: UIImageView!
    @IBOutlet weak var certNameLabel: UILabel!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var localTitleLabel: UILabel!
    
    weak var delegate:CertViewDelegate?
    
    var _status: TrustResultType = .none
    var status: TrustResultType {
        get { return _status }
        set {
            _status = newValue
            if _status == .none {
                statusLabel.textColor = ColorSR
                statusLabel.text = "Not installed".localized
                installBtn.setTitle("Click to install".localized, for: .normal)
                installBtn.isEnabled = true
            }
            if _status == .installed {
                statusLabel.textColor = ColorSY
                statusLabel.text = "Not trust".localized
                installBtn.setTitle("Go to the Settings page to trust the certificate".localized, for: .normal)
                installBtn.isEnabled = true
            }
            if _status == .trusted {
                statusLabel.textColor = ColorSG
                statusLabel.text = "Trusted".localized
                installBtn.setTitle("Trusted".localized, for: .normal)
                installBtn.isEnabled = false
            }
//            if _status == .nofond {
//                statusLabel.textColor = ColorSR
//                statusLabel.text = "Not fond".localized
//                installBtn.setTitle("Click to regenerate".localized, for: .normal)
//                installBtn.isEnabled = true
//            }
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupUI()
    }
    
    func setupUI(){
        localTitleLabel.text = "Current device state".localized
        certNameLabel.textColor = ColorA
        localTitleLabel.textColor = ColorB
        statusLabel.textColor = ColorR
        
        certContentView.isUserInteractionEnabled = true
        certContentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(certDidClick)))
        installBtn.addTarget(self, action: #selector(btnDidClick), for: .touchUpInside)
    }
    
    @objc func certDidClick(){
        delegate?.certViewCertDidClick()
    }
    
    @objc func btnDidClick(){
        delegate?.certViewBtnDidClick(status: status)
    }
    
    static func loadFromNib() -> CertView {
        let v = Bundle.main.loadNibNamed("CertView", owner: nil, options: nil)?.first as! CertView
        return v
    }

}
