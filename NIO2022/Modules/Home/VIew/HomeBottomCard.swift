//
//  HomeBottomCard.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/16.
//

import UIKit
import SnapKit
import NIOMan

class HomeBottomCard: HomeCard {
    
//    var switchDidClick: (() -> Void)?
    var configDidClick: (() -> Void)?
    
    var configButton:HomeConfigButton!
    var _currentConfig: Rule?
    var currentConfig: Rule? {
        get {
            return _currentConfig
        }
        set {
            _currentConfig = newValue
            updataUI()
        }
    }
    
    var launchButton:HomeLaunchButton!
    var _status = NEManager.Status.off
    var status: NEManager.Status {
        get {
            return _status
        }
        set {
            if _status == newValue { return }
            _status = newValue
            updataUI()
        }
    }
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setUI()
        monitor()
        loadData()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func monitor(){
        // 监听当前配置变化
        NotificationCenter.default.addObserver(self, selector: #selector(currentConfiDidChange(noti:)), name: CurrentSelectedRuleChangedNoti, object: nil)
        // 监听VPN状态变化
        NotificationCenter.default.addObserver(self, selector: #selector(vpnStatusDidChange(noti:)), name: VPNSStatusDidChangedNoti, object: nil)
    }
    
    func loadData(){
        // 读取当前VPN状态
        loadVPNStatus()
        // 读取当前配置
        loadConfig()
    }
    
    func setUI() -> Void {
        backgroundColor = .clear
        
        configButton = HomeConfigButton()
        configButton.nameLabel.text = ""
        configButton.isUserInteractionEnabled = true
        configButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(configButtonDidClick)))
        addSubview(configButton)
        
        launchButton = HomeLaunchButton()
        launchButton.status = .off
        launchButton.isUserInteractionEnabled = true
        launchButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(launchButtonDidClick)))
        addSubview(launchButton)
        
        launchButton.snp.makeConstraints { make in
            make.right.equalTo(snp.right)
            make.centerY.equalTo(snp.centerY)
            make.height.equalTo(snp.height)
            make.width.equalTo(106)
        }
        configButton.snp.makeConstraints { make in
            make.centerY.equalTo(snp.centerY)
            make.left.equalTo(snp.left)
            make.height.equalTo(snp.height)
            make.right.equalTo(launchButton.snp.left).offset(-13)
        }
        
    }

    func updataUI() -> Void {
        configButton.nameLabel.text = currentConfig?.name
        launchButton.status = .init(status)
    }
    
    func loadConfig(){
        let gud = UserDefaults(suiteName: GROUPNAME)
        if let currentConfigId = gud?.string(forKey: CURRENTRULEID), let iid = NumberFormatter().number(from: currentConfigId) {
            currentConfig = Rule.find(id: iid)
        }
    }
    
    func loadVPNStatus(){
        NEManager.shared.loadCurrentStatus {[weak self] status in
            self?.status = status
        }
    }
    
    @objc func currentConfiDidChange(noti:Notification){
        loadConfig()
    }
    
    @objc func vpnStatusDidChange(noti:Notification){
        loadVPNStatus()
    }
    
    @objc func configButtonDidClick(){
        configDidClick?()
    }
    
    @objc func launchButtonDidClick(){
        if launchButton.status == .waiting {
            return
        }
        if launchButton.status == .on {
            NEManager.shared.stop()
        }
        if launchButton.status == .off {
            launchButton.status = .waiting
            NEManager.shared.start {[weak self] error in
                if error != nil { print("启动失败:.off" + error.debugDescription) }
                self?.loadVPNStatus()
            }
        }
    }
}

class HomeConfigButton:UIView{
    
    var nameLabel:UILabel!
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI() -> Void {
        backgroundColor = .white
        layer.cornerRadius = 10
        nameLabel = UILabel()
        nameLabel.text = ""
        nameLabel.textColor = ColorB
        nameLabel.font = Font18
        addSubview(nameLabel)
        
        let icon = UIImageView()
        icon.image = UIImage(named: "config-right")
        addSubview(icon)
        icon.snp.makeConstraints { make in
            make.centerY.equalTo(snp.centerY)
            make.right.equalTo(snp.right).offset(-HomeCard.LRMargin)
            make.width.height.equalTo(20)
        }
        
        nameLabel.snp.makeConstraints { make in
            make.centerY.equalTo(snp.centerY)
            make.left.equalTo(snp.left).offset(HomeCard.LRMargin)
            make.right.equalTo(icon.snp.left).offset(-15)
        }
    }
}

class HomeLaunchButton:UIView{
    
    enum LaunchStatus: String {
        case on
        case off
        case waiting
        
        public init(_ status: NEManager.Status) {
            switch status {
            case .on:
                self = .on
            case .off, .invalid:
                self = .off
            case .disconnecting, .connecting:
                self = .waiting
            }
        }
    }
    var _status: LaunchStatus = .off
    var status: LaunchStatus {
        get {
            return _status
        }
        set {
            _status = newValue
            switch _status {
            case .on:
                nameLabel.text = "Stop"
                backgroundColor = ColorSR
            case .off:
                nameLabel.text = "Run"
                backgroundColor = ColorSG
            case .waiting:
                nameLabel.text = "Waiting"
                backgroundColor = ColorSH
            }
        }
    }
    
    var nameLabel:UILabel!
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI() -> Void {
        layer.cornerRadius = 10
        nameLabel = UILabel()
        nameLabel.text = ""
        nameLabel.textColor = .white
        nameLabel.font = Font18
        nameLabel.textAlignment = .center
        addSubview(nameLabel)
        
        backgroundColor = ColorM
        
        nameLabel.snp.makeConstraints { make in
            make.centerY.equalTo(snp.centerY)
            make.centerX.equalTo(snp.centerX)
        }
    }
    
}
