//
//  HomeViewController.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/16.
//


import UIKit
import NetworkExtension
import FileBrowser
import CommonCrypto
import CocoaAsyncSocket
import Reachability
import NIOMan
import SnapKit

let HistoryTaskDidChanged: NSNotification.Name = NSNotification.Name(rawValue: "HistoryTaskDidChanged")//历史数据发生改变，比如删除
let HidenKeyBoradNoti: NSNotification.Name = NSNotification.Name(rawValue: "HidenKeyBoradNoti")
let NetWorkChangedNoti: NSNotification.Name = NSNotification.Name(rawValue: "NetWorkChangedNoti")

let VPNSStatusDidChangedNoti: NSNotification.Name = NSNotification.Name(rawValue: "VPNSStatusDidChangedNoti") //HomeViewController 里监听触发

class HomeViewController: BaseViewController {
    
    let reachability = try! Reachability()
    
    var currentTask:Task?
    var _status = NEManager.Status.off
    var status: NEManager.Status {
        get {
            return _status
        }
        set {
            if _status == newValue { return }
            _status = newValue
            print("VPN状态:" + _status.rawValue)
            if _status == .on {
                currentTastCard.updateDatas(dic: nil)
            }else{
                currentTastCard.dismiss()
                if _status == .off {// 刷新历史任务
                    historyTaskCard.refreshData()
                }
            }
        }
    }
    
    var udpSocket : GCDAsyncUdpSocket?
    
    var _certTrustStatus:TrustResultType = .trusted
    var certTrustStatus: TrustResultType {
        get { return _certTrustStatus }
        set {
            _certTrustStatus = newValue
            certificateStateCard.status = _certTrustStatus
        }
    }
    
    lazy var stackView:UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 10
        return stackView
    }()
    
    // 监听地址端口
    lazy var listeninhCard:HomeListenCard = {
        let v = HomeListenCard()
        v.titleLabel.text = "\("Listening".localized) 127.0.0.1:7890"
        return v
    }()
    // 证书状态
    lazy var certificateStateCard:HomeCertStatuCard = {
        let v = HomeCertStatuCard()
        v.status = certTrustStatus
        v.didClick = {[weak self] in
            if self?.certTrustStatus == TrustResultType.none {
                self?.navigationController?.pushViewController(CertificateViewController(), animated: true)
            }else if self?.certTrustStatus == TrustResultType.installed {
                IDDialog.id_show(title: "Please go to system settings to trust certificate".localized, msg: "Setting CA way".localized, countDownNumber: nil, leftActionTitle: nil, rightActionTitle: "Ok".localized, leftHandler: nil, rightHandler: nil)
            }
        }
        return v
    }()
    // 历史任务
    lazy var historyTaskCard:HomeHistoryCard = {
        let v = HomeHistoryCard()
        v.didClick = {[weak self] in
            self?.navigationController?.pushViewController(HistoryTaskViewController(), animated: true)
        }
        return v
    }()
    // 当前任务
    lazy var currentTastCard:HomeCurrentTaskCard = {
        let v = HomeCurrentTaskCard()
        v.didClick = { [weak self] task in
            if let t = task {
                self?.navigationController?.pushViewController(SessionListViewController(task: t), animated: true)
            }
        }
        return v
    }()
    // 底部操作栏
    lazy var stateCard: HomeBottomCard = {
        let stateCard = HomeBottomCard()
        stateCard.configDidClick = {[weak self] in
            self?.navigationController?.pushViewController(ConfigListViewController(), animated: true)
        }
        return stateCard
    }()
    
    // MARK: Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ColorF
        // Nav
        navBar.titleLable.textColor = ColorB
        navBar.titleLable.font = Font24
        navBar.navLine.isHidden = true
        rightBtn.setImage(UIImage(named: "meun"), for: .normal)
        rightBtn.setTitleColor(ColorM, for: .normal)
        navTitle = "Knot"
        
        // 获取初始状态
        initState()
        // UI
        setUI()
        //
        setMonit()

        if let agree = UserDefaults.standard.string(forKey: ISAGREE) {
            if agree == "yes" {}
        }else{
            let wvc = WebViewController()
            wvc.type = "TCF"
            wvc.modalPresentationStyle = .fullScreen
            present(wvc, animated: false, completion: nil)
        }
        
//        historyTaskCard.refreshList(vpnIsOpen: false)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.addObserver(self, selector:#selector(becomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        // 读取证书信任信息
        checkPermissions()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    override func viewDidLayoutSubviews(){
       super.viewDidLayoutSubviews()
    }
    
    func checkPermissions() -> Void {
        CheckCert.checkPermissions { (result) in
            DispatchQueue.main.async {
                self.certTrustStatus = result
            }
        }
    }
    
    @objc func becomeActive(noti:Notification){
        if certTrustStatus == .trusted {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.checkPermissions()
        }
    }

    override func rightBtnClick() {
        let vc = SettingViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    func setUI() -> Void {
        view.addSubview(stackView)
        stackView.addArrangedSubview(certificateStateCard) // 证书状态
        stackView.addArrangedSubview(listeninhCard) // 监听地址
        stackView.addArrangedSubview(historyTaskCard) // 历史任务
        view.addSubview(stateCard)
        view.addSubview(currentTastCard)
        currentTastCard.isHidden = true
        
        stackView.snp.makeConstraints { make in
            make.centerX.equalTo(view.snp_centerX)
            make.top.equalTo(view.snp_top).offset(navBar.height+8)
            make.width.equalTo(HomeCard.CardWidth)
        }
        
        stateCard.snp.makeConstraints { make in
            make.bottom.equalTo(view.snp.bottom).offset(UIDevice.isX() ? -30 : -15)
            make.width.equalTo(HomeCard.CardWidth)
            make.centerX.equalTo(view.snp_centerX)
            make.height.equalTo(50)
        }
        
        currentTastCard.snp.makeConstraints { make in
            make.top.equalTo(stackView.snp.bottom).offset(10)
            make.bottom.equalTo(stateCard.snp.top).offset(-10)
            make.width.equalTo(HomeCard.CardWidth)
            make.centerX.equalTo(view.snp_centerX)
        }
    }
    
    func initState(){
        // 初始VPN状态
        NEManager.shared.statusDidChangeHandler = {[weak self] status in
            self?.status = status
            NotificationCenter.default.post(name: VPNSStatusDidChangedNoti, object: status)
        }
        NEManager.shared.loadCurrentStatus {[weak self] status in
            self?.status = status
        }
        // UDP通讯
        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
        do{
            try udpSocket?.bind(toPort: 60001)
            try udpSocket?.beginReceiving()
        }catch{
            print("udpSocket bind error:\(error.localizedDescription)")
        }
        
    }
    
    func setMonit(){
        // 网络监控
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
        do{
            try reachability.startNotifier()
        }catch{
            print("could not start reachability notifier")
        }
    }
    
    @objc func reachabilityChanged(note: Notification) {
        let reachability = note.object as! Reachability
        switch reachability.connection {
        case .wifi:
            print("network wifi")
        case .cellular:
            print("network cellular")
        case .none:
            print("network none")
        default: break;
        }
        // 广播
        NotificationCenter.default.post(name: NetWorkChangedNoti, object: nil)
    }
    
}

extension HomeViewController: GCDAsyncUdpSocketDelegate {
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        let jsonStr = String(data: data, encoding: .utf8) ?? ""
//        print(jsonStr)
        let dic = [String:Any].fromJson(jsonStr)
        if dic["type"] as! String == "task" {
            if dic["action"] as! String == "create" {
                currentTastCard.updateDatas(dic: nil)
            }
            if dic["action"] as! String == "update" {
                currentTastCard.updateDatas(dic: dic["data"] as? [String:Any])
            }
        }
    }
}
