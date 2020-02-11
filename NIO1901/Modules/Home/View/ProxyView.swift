//
//  ProxyView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/28.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

enum ServerType {
    case WIFI
    case LOCAL
}

protocol ProxyViewDelegate: class {
    func proxyTipBtnDidClick()
    func proxyServerChange(type:ServerType,value:Bool)
}

class ProxyView: UIView {
    
    var _task:Task?
    var task:Task?{
        set{
            _task = newValue
            updateUI()
        }
        get{
            return _task
        }
    }
    
    weak var delegate:ProxyViewDelegate?
    
    lazy var localServerView: ServerView = {
        let localServerView = ServerView()
        localServerView.titleLabel.text = "Local Listening".localized
        localServerView.switchValueDidChanged = { isOn in
            self.delegate?.proxyServerChange(type: .LOCAL, value: isOn)
        }
        return localServerView
    }()
    
    lazy var wifiServerView: ServerView = {
        let wifiServerView = ServerView()
        wifiServerView.titleLabel.text = "Wifi Listening".localized
        wifiServerView.switchValueDidChanged = { isOn in
            self.delegate?.proxyServerChange(type: .WIFI, value: isOn)
        }
        return wifiServerView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        addTitle()
        addServers()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addTitle() {
        let titleView = UIView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 34))
        titleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleViewDidClick)))
        titleView.isUserInteractionEnabled = true
        let iconView = UIImageView(image: UIImage(named: "knot"))
        titleView.addSubview(iconView)
        let titleLabel = UILabel()
        titleLabel.text = "Listening Proxy Settings".localized
        titleLabel.textColor = ColorA
        titleLabel.font = Font18
        titleView.addSubview(titleLabel)
        let helpBtn = UIImageView(image: UIImage(named: "help"))
        helpBtn.isHidden = true
        titleView.addSubview(helpBtn)
        iconView.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing)
            m.centerY.equalToSuperview()
            m.width.height.equalTo(15)
        }
        titleLabel.snp.makeConstraints { (m) in
            m.left.equalTo(iconView.snp.right).offset(12)
            m.centerY.equalToSuperview()
        }
        helpBtn.snp.makeConstraints { (m) in
            m.right.equalToSuperview().offset(-LRSpacing)
            m.width.equalTo(20)
            m.height.equalTo(20)
            m.centerY.equalToSuperview()
        }
        addSubview(titleView)
    }
    
    @objc func titleViewDidClick(){
        delegate?.proxyTipBtnDidClick()
    }
    
    func addServers(){
        addSubview(localServerView)
        localServerView.frame = CGRect(x: 0, y: 34, width: SCREENWIDTH, height: 97)
        
        let lineView = UIView(frame: CGRect(x: LRSpacing, y: 34+97, width: SCREENWIDTH - LRSpacing * 2, height: 1))
        lineView.backgroundColor = ColorE
        addSubview(lineView)
        wifiServerView.isHidden = false
        addSubview(wifiServerView)
        wifiServerView.frame = CGRect(x: 0, y: 34 + 97 + 1, width: SCREENWIDTH, height: 97)
    }
    
    func updateUI(){
        guard let t = task else {
            return
        }
        localServerView.ipLabel.text = t.localIP
        localServerView.portLabel.text = "\(t.localPort)"
        localServerView.stateSwitch.isOn = t.localEnable == 1
        
        wifiServerView.ipLabel.text = t.wifiIP
        if t.wifiPort == -1 {
            wifiServerView.portLabel.text = ""
        }else{
            wifiServerView.portLabel.text = "\(t.wifiPort)"
        }
        wifiServerView.stateSwitch.isOn = t.wifiEnable == 1
    }

}

class ServerView: UIView {
    
    var switchValueDidChanged:((Bool) -> Void)?
    
    var titleLabel:UILabel = UILabel()
    var stateSwitch:UISwitch = UISwitch()
    var ipLabel = UILabel()
    var portLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        addSubview(stateSwitch)
        addSubview(ipLabel)
        addSubview(portLabel)
        layout()
        stateSwitch.isOn = false
        stateSwitch.addTarget(self, action: #selector(switchDidChanged(sender:)), for: .touchUpInside)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func layout() {
        titleLabel.textColor = ColorA
        titleLabel.font = Font16
        titleLabel.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing-44)
            m.height.equalTo(37)
        }
        stateSwitch.snp.makeConstraints { (m) in
            m.right.equalToSuperview().offset(-LRSpacing)
            m.left.equalTo(titleLabel.snp.right)
            m.centerY.equalTo(titleLabel.snp.centerY)
        }
        
        
        let ip = UILabel()
        ip.text = "Server".localized
        addSubview(ip)
        ip.textColor = ColorA
        ip.font = Font16
        ip.snp.makeConstraints { (m) in
            m.left.equalTo(titleLabel.snp.left)
            m.height.equalTo(30)
            m.top.equalTo(titleLabel.snp.bottom)
        }
        ipLabel.textColor = ColorB
        ipLabel.font = Font16
        ipLabel.snp.makeConstraints { (m) in
            m.right.equalToSuperview().offset(-LRSpacing)
            m.height.top.equalTo(ip)
        }
        ipLabel.text = "127.0.0.1"
        
        
        let port = UILabel()
        port.text = "Port".localized
        addSubview(port)
        
        port.textColor = ColorA
        port.font = Font16
        port.snp.makeConstraints { (m) in
            m.left.equalTo(titleLabel.snp.left)
            m.height.equalTo(30)
            m.top.equalTo(ip.snp.bottom)
        }
        portLabel.snp.makeConstraints { (m) in
            m.right.equalToSuperview().offset(-LRSpacing)
            m.height.top.equalTo(port)
        }
        portLabel.text = ""
        portLabel.textColor = ColorB
        portLabel.font = Font16
    }
    
    @objc func switchDidChanged(sender:UISwitch) {
        switchValueDidChanged?(sender.isOn)
    }
}
