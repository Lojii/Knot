//
//  StateView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/28.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NetworkExtension
import TunnelServices

class StateCard: UIView {
    
    let tip1 = "CA certificate is not installed at present, so HTTPS traffic cannot be grabbed. Click to the certificate management page to set the certificate".localized
    let tip2 = "CA certificate has been installed, but the certificate has not been trusted, so HTTPS traffic cannot be crawled. Click to the certificate management page for details".localized
    let tip3 = "CA certificate installed".localized
    
    var stateViewHeight:CGFloat = 50
    var _certTrustStatus:TrustResultType = .none
    var certTrustStatus: TrustResultType {
        get { return _certTrustStatus }
        set {
            _certTrustStatus = newValue
            if _certTrustStatus == .none {
                certTipView.isHidden = false
                tipLabel.text = tip1
            }
            if _certTrustStatus == .installed {
                certTipView.isHidden = false
                tipLabel.text = tip2
            }
            let tipViewHeight = tipLabel.text?.textHeight(font: tipLabel.font, fixedWidth: SCREENWIDTH - LRSpacing * 2) ?? 0
            stateViewHeight = 50 + tipViewHeight + 20
            
            if _certTrustStatus == .trusted {
                tipLabel.text = tip3
                certTipView.isHidden = true
                stateViewHeight = 50
            }
            setLayout()
        }
    }
    var _vpnStatus: NEVPNStatus = .disconnected
    var vpnStatus: NEVPNStatus {
        get { return _vpnStatus }
        set {
            _vpnStatus = newValue
            
            if _vpnStatus == .connected {
                // 按钮可用
                startButton.isEnabled = true
//                startButton.isSelected = true
//                startButton.titleLabel?.text = "Close"
                startButton.setTitle("Close", for: .normal)
                startButton.backgroundColor = ColorR
                filterLabel.textColor = ColorC
//                iconView.image = UIImage(named: "down")?.imageWithTintColor(color: ColorC)
            }else {
                if _vpnStatus == .disconnected {
                    // 按钮可用
                    startButton.isEnabled = true
//                    startButton.isSelected = false
//                    startButton.titleLabel?.text = "Run"
                    startButton.setTitle("Run", for: .normal)
                    startButton.backgroundColor = ColorM
                    filterLabel.textColor = ColorA
//                    iconView.image = UIImage(named: "down")?.imageWithTintColor(color: ColorA)
                }else{
                    // 按钮loading状态，不可用
                    startButton.isEnabled = false
//                    startButton.titleLabel?.text = "Waiting"
                    startButton.setTitle("Waiting", for: .normal)
                    startButton.backgroundColor = ColorD
                    filterLabel.textColor = ColorC
//                    iconView.image = UIImage(named: "down")?.imageWithTintColor(color: ColorC)
                }
            }
        }
    }
    var switchDidClick: (() -> Void)?
    var configDidClick: (() -> Void)?
    var tipDidClick: (() -> Void)?
    
    var filterConfig:String = "Default"
    lazy var filterLabel:UILabel = {
        let filterLabel = UILabel()
        filterLabel.text = self.filterConfig
        filterLabel.font = Font18
        filterLabel.textColor = ColorA
        return filterLabel
    }()
    lazy var startButton:UIButton = {
        let startButton = UIButton()
        startButton.backgroundColor = ColorM
        startButton.setTitle("Run", for: .normal)
        startButton.setTitle("Close", for: .selected)
        startButton.setTitle("Waiting", for: .disabled)
        startButton.setTitleColor(.white, for: .normal)
        startButton.addTarget(self, action: #selector(btnDidClick), for: .touchUpInside)
        startButton.layer.cornerRadius = 14
        startButton.clipsToBounds = true
        return startButton
    }()
    var iconView: UIImageView!
    var downView: UIImageView!
    
    var ruleView:UIView!
    
    var tipLabel:UILabel!
    var certTipView:UIView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        
        // rule view
        ruleView = UIView()
        ruleView.isUserInteractionEnabled = true
        ruleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(configClick)))
        iconView = UIImageView(image: UIImage(named: "filter"))
        ruleView.addSubview(iconView)
        ruleView.addSubview(filterLabel)
        downView = UIImageView(image: UIImage(named: "down"))
        ruleView.addSubview(downView)
        addSubview(ruleView)
        // start button
        addSubview(startButton)
        // cert view
        certTipView = UIView()
        certTipView.isUserInteractionEnabled = true
        certTipView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tipViewDidClick)))
        tipLabel = UILabel.initWith(color: ColorC, font: Font14, text: "", frame: CGRect.zero)
        tipLabel.numberOfLines = 0
        tipLabel.textAlignment = .center
//        tipLabel.text =
        tipLabel.text = tip1
        certTipView.addSubview(tipLabel)
        certTipView.addLine(offY: 1, lineWidth: SCREENWIDTH)
        addSubview(certTipView)
        
        setLayout()
        
        loadData()
    }
    
    func loadData(){
        var rule:Rule?
        if let currentRuleId = UserDefaults.standard.string(forKey: CurrentRuleId),let value = Int(currentRuleId) {
            if let currentRule = Rule.findFirst("id", value: NSNumber(integerLiteral: value)) {
                filterLabel.text = currentRule.name
                rule = currentRule
            }
        }
        if rule == nil {
            if let lastRule = Rule.findFirst(orders: ["id":true]) {
                rule = lastRule
                filterLabel.text = lastRule.name
            }
        }
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setLayout(){
        startButton.snp.makeConstraints { (m) in
            m.width.equalTo(75)
            m.height.equalTo(28)
            m.right.equalToSuperview().offset(-LRSpacing)
            m.centerY.equalTo(ruleView.snp.centerY)
        }
        // ruleView
        ruleView.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview()
            m.height.equalTo(50)
            m.right.equalTo(startButton.snp.left)
        }
        iconView.snp.makeConstraints { (m) in
            m.width.height.equalTo(15)
            m.centerY.equalToSuperview()
            m.leftMargin.equalToSuperview().offset(LRSpacing)
        }
        filterLabel.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.left.equalTo(iconView.snp.right).offset(15)
            m.width.lessThanOrEqualTo(SCREENWIDTH - LRSpacing * 2 - 15 - 75 - 20 - 10)
        }
        downView.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.left.equalTo(filterLabel.snp.right)//.offset(3)
            m.width.height.equalTo(20)
        }
        // tipView
        certTipView.snp.makeConstraints { (m) in
            m.top.equalTo(ruleView.snp.bottom)
            m.left.right.bottom.equalToSuperview()
        }
        tipLabel.snp.makeConstraints { (m) in
            m.top.bottom.equalToSuperview()
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing)
        }
    }
    
    @objc func configClick() -> Void {
        configDidClick?()
    }
    
    @objc func btnDidClick(){
        switchDidClick?()
    }
    
    @objc func tipViewDidClick(){
        tipDidClick?()
    }
    
}
