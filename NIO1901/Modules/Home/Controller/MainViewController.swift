//
//  MainViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices
import NetworkExtension
import FileBrowser
import CommonCrypto
import CocoaAsyncSocket
import MMWormhole
import Reachability

let HistoryTaskDidChanged: NSNotification.Name = NSNotification.Name(rawValue: "HistoryTaskDidChanged")
let HidenKeyBoradNoti: NSNotification.Name = NSNotification.Name(rawValue: "HidenKeyBoradNoti")
let NetWorkChangedNoti: NSNotification.Name = NSNotification.Name(rawValue: "NetWorkChangedNoti")



class MainViewController: BaseViewController {
    
    let reachability = try! Reachability()
    var currentIsWifi = false
    var netStr = ""
    var _vpnStatus: NEVPNStatus = .disconnected
    var vpnStatus: NEVPNStatus {
        get { return _vpnStatus }
        set {
            _vpnStatus = newValue
            print("VPN Status:\(_vpnStatus)")
            stateCard.vpnStatus = _vpnStatus
            layoutSubViews()
            historyView.refreshList(vpnIsOpen: _vpnStatus == .connected)
            updateData()
        }
    }
    var mitmServer: MitmService?
    var vpnManager: SFVPNManager!
    var currentTask:Task?
    var udpSocket : GCDAsyncUdpSocket?
    var wormhole:MMWormhole?
    
    var certTrustStatus:TrustResultType = .none
    var showCertTip = true
    
    lazy var scrollView:UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.frame = CGRect(x: 0, y: navBar.frame.height, width: SCREENWIDTH, height: SCREENHEIGHT - navBar.frame.height)
        return scrollView
    }()
    // 顶部开关状态
    lazy var stateCard: StateCard = {
        let stateCard = StateCard()
        stateCard.switchDidClick = {
            self.switchVPN()
        }
        stateCard.configDidClick = {
            if self.vpnStatus != .disconnected { return }
            let popup = PopupController.create(self)
                .customize(
                    [
                        .layout(.bottom),
                        .animation(.slideUp),
                        .backgroundStyle(.blackFilter(alpha: 0.5)),
                        .dismissWhenTaps(true),
                        .scrollable(true)
                    ]
            )
            let vc = RuleListViewController()
            vc.closeHandler = { popup.dismiss() }
            vc.itemSelectedHandler = { _ in
                
            }
            popup.show(vc)
        }
        stateCard.tipDidClick = {
            self.navigationController?.pushViewController(CertificateViewController(), animated: true)
        }
        return stateCard
    }()
    // 历史任务
    lazy var historyView: HistoryView = {
        let historyView = HistoryView()
        historyView.delegate = self
        return historyView
    }()
    
    lazy var proxyView: ProxyView = {
        let proxyView = ProxyView()
        proxyView.delegate = self
        return proxyView
    }()
    
    lazy var taskView: TastView = {
        let taskView = TastView()
        taskView.isUserInteractionEnabled = true
        taskView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(currentTaskDidClick)))
        return taskView
    }()

    // MARK: Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Nav
        navBar.titleLable.text = "Knot"
        navBar.titleLable.textColor = ColorA
        navBar.titleLable.font = Font24
//        rightBtn.setTitle("Settings".localized, for: .normal)
        rightBtn.setImage(UIImage(named: "settings"), for: .normal)
        rightBtn.setTitleColor(ColorM, for: .normal)
//        navBar.titleLable.isUserInteractionEnabled = true
//        navBar.titleLable.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(showLog)))
        // UI
        setUI()
        // 读取证书信任信息
//        checkPermissions()
        // 通知
        NotificationCenter.default.addObserver(self, selector: #selector(selectedRuleDidChanged(noti:)), name: CurrentSelectedRuleChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(vpnDidChange(noti:)), name: NSNotification.Name.NEVPNStatusDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector:#selector(becomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector:#selector(historyDidChanged), name: HistoryTaskDidChanged, object: nil)
        // UDP通讯
        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
        do{
            try udpSocket?.bind(toPort: 60001)
        }catch{
            print("udpSocket bind error:\(error.localizedDescription)")
        }
        // 网络监控
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(note:)), name: .reachabilityChanged, object: reachability)
        do{
            try reachability.startNotifier()
        }catch{
            print("could not start reachability notifier")
        }
        // 另一个大名鼎鼎的监控
        wormhole = MMWormhole.init(applicationGroupIdentifier: GROUPNAME, optionalDirectory: "wormhole")
        //
        profileStatus()
        //
        historyView.refreshList(vpnIsOpen: _vpnStatus == .connected)
        
        if let agree = UserDefaults.standard.string(forKey: ISAGREE) {
            if agree == "yes" {}
        }else{
            let wvc = WebViewController()
            wvc.type = "TCF"
            wvc.modalPresentationStyle = .fullScreen
            present(wvc, animated: false, completion: nil)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        try? udpSocket?.beginReceiving()
        updateData()
        checkPermissions()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        udpSocket?.pauseReceiving()
    }
    
    deinit {
        udpSocket?.close()
    }
    
    func checkPermissions() -> Void {
        CheckCert.checkPermissions { (result) in
            DispatchQueue.main.async {
                self.certTrustStatus = result
                if Nan.isNan() {
                    self.stateCard.certTrustStatus = result
                }else{
                    self.stateCard.certTrustStatus = .trusted
                }
                self.layoutSubViews()
            }
        }
    }
    
    override func rightBtnClick() {
        checkPermissions()
        return
        
        let vc = SettingViewController()
        vc.currentNet = netStr
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc func reachabilityChanged(note: Notification) {
        let reachability = note.object as! Reachability
        switch reachability.connection {
        case .wifi:
            netStr = "wifi"
            currentIsWifi = true
        case .cellular:
            netStr = "cellular"
            currentIsWifi = false
        case .none:
            netStr = "none"
            currentIsWifi = false
        default: break;
        }
        NotificationCenter.default.post(name: NetWorkChangedNoti, object: netStr)
        updateData()
    }
    
    @objc  func becomeActive(noti:Notification){
        checkPermissions()
    }
    
    @objc  func historyDidChanged(noti:Notification){
        historyView.refreshList(vpnIsOpen: vpnStatus == .connected)
    }
    
    @objc func currentTaskDidClick(){
        if let task = Task.findFirst(orders: ["id":false]) {
            navigationController?.pushViewController(SessionListViewController(task: task), animated: true)
        }
    }
    
    @objc func selectedRuleDidChanged(noti:Notification){
        if let rule = noti.object as? Rule {
            stateCard.filterLabel.text = rule.name
        }
    }
    // 重新充数据库读取最新的task
    @objc func updateData(){
        if vpnStatus == .connected {
            do{
                currentTask = Task.getLast(false)
            }catch{
                print("读取最后一个报错了！")
            }
            if !currentIsWifi {
                currentTask?.wifiEnable = 0
                currentTask?.wifiIP = ""
                currentTask?.wifiPort = -1
            }
        }else{
            currentTask = nil
        }
        
        proxyView.task = currentTask
        taskView.task = currentTask
    }
    
    func setUI() -> Void {
        view.addSubview(scrollView)
        scrollView.addSubview(stateCard) // 顶部开关
        // tipsView
        scrollView.addSubview(proxyView) // 代理设置
        scrollView.addSubview(taskView)  // 当前任务
        scrollView.addSubview(historyView) // 历史任务
        layoutSubViews()
    }
    
    func layoutSubViews() -> Void {
        var offsetY:CGFloat = 0
        let clearance:CGFloat = 12
        stateCard.frame = CGRect(x: 0, y: offsetY, width: SCREENWIDTH, height: stateCard.stateViewHeight)
        offsetY = offsetY + stateCard.frame.size.height + clearance
        if vpnStatus == .connected {
            proxyView.isHidden = false
            proxyView.frame = CGRect(x: 0, y: offsetY, width: SCREENWIDTH, height: 228)
            offsetY = offsetY + proxyView.frame.size.height + clearance
            taskView.isHidden = false
            taskView.frame = CGRect(x: 0, y: offsetY, width: SCREENWIDTH, height: 125)
            offsetY = offsetY + taskView.frame.size.height + clearance
        }else{
            proxyView.isHidden = true
            taskView.isHidden = true
        }
        UIView.animate(withDuration: 0.25) {
            self.historyView.frame = CGRect(x: 0, y: offsetY, width: SCREENWIDTH, height: 434)
        }
        offsetY = offsetY + historyView.frame.size.height + clearance
        scrollView.contentSize = CGSize(width: 0, height: offsetY - clearance)
    }
    
    @objc func showLog(){
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
        let fileBrowser = FileBrowser(initialPath: directory, allowEditing: true, showCancelButton: true)
        present(fileBrowser, animated: true, completion: nil)
    }
    // MARK:VPN
    func switchVPN() -> Void {
        if StartInExtension {
            if vpnStatus == .connected {
                currentTask = nil
                startStopToggled()
            }else{
                if Nan.isNan() {
                    if certTrustStatus != .trusted {
                        var msg = "Whether to install CA certificates, parse the HTTPS packets".localized
                        var rightTitle = "Now open".localized
                        if certTrustStatus == .installed {
                            msg = "CA certificates need to be trusted in order to parse HTTPS packets".localized
                            rightTitle = "To trust".localized
                        }
                        IDDialog.id_show(title: "HTTPS Settings".localized, msg: msg, countDownNumber: nil, leftActionTitle: "Later".localized, rightActionTitle: rightTitle, leftHandler: {
                            let task = Task.newTask()
                            try? task.save()
                            self.currentTask = task
                            self.startStopToggled()
                            return
                        }) {
                            self.navigationController?.pushViewController(CertificateViewController(), animated: true)
                            return
                        }
                    }else{
                        let task = Task.newTask()
                        try? task.save()
                        currentTask = task
                        startStopToggled()
                    }
                }else{
                    let task = Task.newTask()
                    try? task.save()
                    currentTask = task
                    startStopToggled()
                }
            }
        }else{
            if vpnStatus == .connected {
                mitmServer?.close()
                currentTask = nil
            }else{
                let task = Task.newTask()
                try? task.save()
                currentTask = task
                // 启动，临时方式
                mitmServer = MitmService.prepare()
                if mitmServer == nil {
                    print("服务启动失败！")
                    return
                }
                mitmServer?.run({ (result) in
                    switch result {
                    case .success( _):
                        print("服务开启成功！")
                    case .failure(let error):
                        print("服务开启失败:\(error.localizedDescription)")
                        // todo:删除创建的task
                        try? task.delete()
                        break
                    }
                })
            }
            startStopToggled()
        }
    }
    
    @objc func vpnDidChange(noti:Notification) -> Void {
        guard let tunnelPS = noti.object as? NETunnelProviderSession else {
            print("Not NETunnelProviderSession !")
            return
        }
        if vpnStatus != tunnelPS.status {
            vpnStatus = tunnelPS.status
        }
    }
    
    func profileStatus() {
        NETunnelProviderManager.loadAllFromPreferences() { (managers, error) -> Void in
            if let ms = managers,ms.count > 0 {
                if let m  = ms.first {
                    SFVPNManager.shared.manager = m
                }
            }
        }
    }
    
    func startStopToggled() {
        do  {
            self.profileStatus()
            let result = try SFVPNManager.shared.startStopToggled()
            if !result {
                SFVPNManager.shared.loadManager({[unowned self] (manager, error) in
                    if let error = error {
                        if error.localizedDescription.contains("permission denied") {
                            ZKProgressHUD.showError("授权失败 !")
                        }else{
                            print("SFVPNManager.shared.loadManager error:\(error)")
                        }
                    }else {
                        self.startStopToggled()
                    }
                })
            }else{
                
            }
        } catch let error as NSError{
            print("VPN 开启失败 !\(error.localizedDescription)")
            ZKProgressHUD.showError("\(error.localizedDescription)")
        }
    }
    
    @objc func registerStatus(){
        print("-------registerStatus-------")
        if SFVPNManager.shared.manager == nil {
            loadManager()
        }
//        if let m = SFVPNManager.shared.manager {
////            print("profile status: \(m)")
//        }else {
//            self.loadManager()
//        }
    }
    
    func loadManager() {
        let vpnmanager = SFVPNManager.shared
        if !vpnmanager.loading {
            vpnmanager.loadManager() { [weak self] (manager, error) -> Void in
                if let _ = manager {
                    self!.registerStatus()
                }
            }
        }
    }
    
}


extension MainViewController: GCDAsyncUdpSocketDelegate {
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        let jsonStr = String(data: data, encoding: .utf8)
        let dic = [String:String].fromJson(jsonStr ?? "")
        if dic["url"] != nil || dic[""] != nil {
            taskView.updateTask(dic: dic)
        }else if let state = dic["state"] {
            if state == "close" {
//                vpnIsOpen = false
//                print("vpn closed !")
//                ZKProgressHUD.dismiss()
//                layoutSubViews()
//                historyView.refreshList(vpnIsOpen: vpnIsOpen)
//                updateData()
            }
        }
    }
}

extension MainViewController: HistoryViewDelegate,ProxyViewDelegate {
    
    func proxyTipBtnDidClick() {
        lsof.getlsofArray()
    }
    
    func proxyServerChange(type: ServerType, value: Bool) {
        var dic = [String:String]()
        if type == .LOCAL {
            dic["localEnable"] = value ? "1" : "0"
        }else{
            dic["wifiEnable"] = value ? "1" : "0"
            if !currentIsWifi {
                ZKProgressHUD.showMessage("You must connect to a wireless network to enable LAN monitoring".localized)
                self.updateData()
                return
            }
        }
        wormhole?.passMessageObject(dic.toJson() as NSCoding, identifier: TaskConfigDidChanged)
//        ZKProgressHUD.show()
        DispatchQueue.global().async {
            sleep(1)
            DispatchQueue.main.async {
                ZKProgressHUD.dismiss()
                self.updateData()
            }
        }
        
    }
    
    func taskDidClick(task: Task) {
        navigationController?.pushViewController(SessionListViewController(task: task), animated: true)
    }
    
    func taskModeDidClick() {
        let vc = HistoryTaskViewController()
        vc.vpnStatus = vpnStatus
        navigationController?.pushViewController(vc, animated: true)
    }
}
