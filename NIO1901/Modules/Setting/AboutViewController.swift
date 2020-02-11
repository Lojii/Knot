//
//  AboutViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/28.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import AxLogger

class AboutViewController: BaseViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        navTitle = "About".localized
        navBar.navLine.isHidden = true
        setupUI()
    }
    
    func setupUI(){
        view.backgroundColor = .white
        let iconView = UIImageView(image: UIImage(named: "icon-60"))
        iconView.contentMode = .scaleAspectFit
        view.addSubview(iconView)
        
        let appVersion = AxEnvHelper.appVersion()
        let nameLabel = UILabel()
        nameLabel.text = "Knot v\(appVersion)"
        nameLabel.textAlignment = .center
        nameLabel.font = Font18
        nameLabel.textColor = ColorD
        view.addSubview(nameLabel)
        
        iconView.snp.makeConstraints { (m) in
            m.center.equalToSuperview()
            m.width.height.equalTo(150)
        }
        nameLabel.snp.makeConstraints { (m) in
            m.centerX.equalToSuperview()
//            m.top.equalTo(iconView.snp.bottom)
            m.bottom.equalToSuperview().offset(-20-XBOTTOMHEIGHT)
        }
    }

}
