//
//  CertificateViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/19.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices
import Security

class CertificateViewController: BaseViewController {
    
    var httpServer:LocalHTTPServer?
    var scrollView:UIScrollView!
    var certView:CertView!
    var localTipLable:UILabel!
    var otherTipLable:UILabel!
    
    let tipWidth = SCREENWIDTH - LRSpacing * 2
    
    let localTip = "Local install".localized
//    """
//本机安装(两个步骤):
//1、点击安装->跳转Safari->允许下载配置描述文件->设置->已下载描述文件->安装
//2、设置->通用->关于本机->证书信任设置->选中->完成
//注意：【已验证】不同于【已信任】
//"""
    let otherTip1 = "Other device install".localized
//    """
//其他设备安装(两种方式):
//a、点击证书导出->分享到其他设备->安装并信任
//b、该手机与其他设备接入同一无线网WiFi，在其他设备上用浏览器打开
//"""
    let otherTip2 = "Other device install2".localized
//    """
//,下载安装
//注意：通过无线网安装的时候，【请保持本页面打开】
//"""
    
    var ipStr = "Local IP address".localized
    
    var _wifiIsOpen:Bool = false
    var wifiIsOpen: Bool {
        get { return _wifiIsOpen }
        set {
//            print("wifi:\(newValue)")
            _wifiIsOpen = newValue
            if _wifiIsOpen {
                let wifiIP = NetworkInfo.LocalWifiIPv4()
                if wifiIP != "" {
                    ipStr = "http://\(wifiIP)"
                }else{
                    ipStr = "Local IP address".localized
                }
            }else{
                ipStr = "Local IP address".localized
            }
            updateLayout()
        }
    }
    var _certTrustStatus:TrustResultType = .none
    var certTrustStatus: TrustResultType {
        get { return _certTrustStatus }
        set {
            _certTrustStatus = newValue
            certView.status = _certTrustStatus
        }
    }
    var certificate: SecCertificate?
    var certificateName:String?

    override func viewDidLoad() {
        super.viewDidLoad()
        navTitle = "HTTPS certificate management".localized
        loadCert()
        setupUI()
        // 网络变化监听
        NotificationCenter.default.addObserver(self, selector: #selector(httpServerDidChanged(noti:)), name: LocalHTTPServerChanged, object: nil)
        httpServer = LocalHTTPServer()
        httpServer?.run()
        //
        NotificationCenter.default.addObserver(self, selector:#selector(becomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        
    }
    
    func loadCert(){
        // 先检查是否安装证书
        if let certPath = MitmService.getCertPath()?.appendingPathComponent("cacert.der"),
            let certData = try? Data(contentsOf: certPath) {
            guard let cert = SecCertificateCreateWithData(nil, certData as CFData) else {
                print("no cert file !")
                return
            }
            certificate = cert
            certificateName = SecCertificateCopySubjectSummary(certificate!) as String?
        }
    }
    
    func displayCertificate(_ certificate: SecCertificate) -> String {
        let subject = SecCertificateCopySubjectSummary(certificate) as String?
        return "Cert Subject: \(subject ?? "nil")\n"
    }
    
    func setupUI(){
        scrollView = UIScrollView(frame: CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: view.width, height: view.height - NAVGATIONBARHEIGHT))
        view.addSubview(scrollView)
        certView = CertView.loadFromNib()
        certView.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 130)
        certView.status = .none
        certView.certNameLabel.text = certificateName
        certView.delegate = self //[weak self]
        scrollView.addSubview(certView)
        
        
        
        let localTipHeight = localTip.textHeight(font: Font14, fixedWidth: tipWidth)
        localTipLable = UILabel()
        localTipLable.numberOfLines = 0
        localTipLable.text = localTip
        localTipLable.textColor = ColorC
        localTipLable.font = Font14
        localTipLable.frame = CGRect(x: LRSpacing, y: certView.frame.maxY + 20, width: tipWidth, height: localTipHeight)
        scrollView.addSubview(localTipLable)
        
        
        let otherTip = otherTip1 + ipStr + otherTip2
        let otherTipHeight = otherTip.textHeight(font: Font14, fixedWidth: tipWidth)
        otherTipLable = UILabel()
        otherTipLable.numberOfLines = 0
        otherTipLable.text = otherTip
        otherTipLable.textColor = ColorC
        otherTipLable.font = Font14
        otherTipLable.frame = CGRect(x: LRSpacing, y: localTipLable.frame.maxY + 20, width: tipWidth, height: otherTipHeight)
        scrollView.addSubview(otherTipLable)
    }
    
    func updateLayout() {
        let otherTip = otherTip1 + ipStr + otherTip2
        let otherTipHeight = otherTip.textHeight(font: Font14, fixedWidth: tipWidth)
        otherTipLable.text = otherTip
        otherTipLable.frame = CGRect(x: LRSpacing, y: localTipLable.frame.maxY + 20, width: tipWidth, height: otherTipHeight)
    }
    
    @objc func httpServerDidChanged(noti:Notification){
        if let dic = noti.object as? [String:Bool] {
            if dic["wifi"] != nil {
                wifiIsOpen = dic["wifi"]!
            }
        }
    }
    
    @objc  func becomeActive(noti:Notification){
        checkPermissions()
    }
    
    func checkPermissions() -> Void {
        CheckCert.checkPermissions { (result) in
            DispatchQueue.main.async {
                self.certTrustStatus = result
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        checkPermissions()
    }
    
    deinit {
        httpServer?.close()
        NotificationCenter.default.removeObserver(self)
        print("CertificateViewController deinit !")
    }

}


extension CertificateViewController:CertViewDelegate {
    
    func certViewCertDidClick() {
        // 弹窗分享
        if let certPath = MitmService.getCertPath()?.appendingPathComponent("cacert.der"){
            VisualActivityViewController.share(file: certPath.absoluteString, on: self)
        }
    }
    
    func certViewBtnDidClick(status: TrustResultType) {
        // 跳转Safari或者设置
        if status == .none {
            let url = URL(string: "http://localhost")
            UIApplication.shared.openURL(url!)
        }
        if status == .installed {
            IDDialog.id_show(title: "Please go to system settings to trust certificate".localized, msg: "Setting CA way".localized, countDownNumber: nil, leftActionTitle: nil, rightActionTitle: "Ok".localized, leftHandler: nil, rightHandler: nil)
        }
    }
}
