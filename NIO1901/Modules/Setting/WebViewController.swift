//
//  WebViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/9/8.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import WebKit


let ISAGREE = "isAgree"

class WebViewController: BaseViewController,WKNavigationDelegate {
    
    var webview:WKWebView!
    var type = "TC"  // TC：服务条款  TCF：第一次显示的服务条款  PP：隐私政策
    var tryAgain:UIButton!
    lazy private var progressView: UIProgressView = {
        self.progressView = UIProgressView.init(frame: CGRect(x: 0, y: navBar.height, width: SCREENWIDTH, height: 2))
        self.progressView.tintColor = UIColor.blue      // 进度条颜色
        self.progressView.trackTintColor = UIColor.white // 进度条背景色
        return self.progressView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navBgColor = .white
        webview = WKWebView(frame: view.bounds)
        webview.navigationDelegate = self;
        webview.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        view.backgroundColor = .white
        view.addSubview(webview)
        view.addSubview(progressView)
        
        tryAgain = UIButton(frame: CGRect(x: 0, y: (SCREENHEIGHT - 200) / 2, width: SCREENWIDTH, height: 200))
        tryAgain.setTitle("Network Error ！Click Retry".localized, for: .normal)
        tryAgain.setTitleColor(UIColor.black, for: .normal)
        tryAgain.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        tryAgain.isHidden = true
        tryAgain.addTarget(self, action: #selector(loadTCHtml), for: .touchUpInside)
        webview.addSubview(tryAgain)
        
        if type == "PP" {
            navTitle = "Privacy Policy".localized
            loadPPHtml()
        }else{
            navTitle = "Terms & Conditions".localized
            if type == "TCF" {
                showLeftBtn = false
                rightBtn.setTitle("Next".localized, for: .normal)
                rightBtn.setTitleColor(ColorM, for: .normal)
                rightBtn.isHidden = true
            }
            loadTCHtml()
        }
    }
    /// 加载服务条款
    @objc func loadTCHtml() -> Void {
//        let fwtkRequest = URLRequest(url: URL(string: fwtkUrl)!,cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
//        // reloadRevalidatingCacheData
        if let bundleHttpPath = Bundle.main.url(forResource: "Http/fwtkcn", withExtension: "html") {
            webview.loadFileURL(bundleHttpPath, allowingReadAccessTo: Bundle.main.bundleURL)
        }
//        webview.load(fwtkRequest)
    }
    
    func loadPPHtml() -> Void {
        if let currentLanguage = Locale.preferredLanguages.first, currentLanguage.contains("zh") {
            if let bundleHttpPath = Bundle.main.url(forResource: "Http/yszccn", withExtension: "html") {
                webview.loadFileURL(bundleHttpPath, allowingReadAccessTo: Bundle.main.bundleURL)
            }
        }else{
            if let bundleHttpPath = Bundle.main.url(forResource: "Http/yszcen", withExtension: "html") {
                webview.loadFileURL(bundleHttpPath, allowingReadAccessTo: Bundle.main.bundleURL)
            }
        }
    }
    
    override func rightBtnClick() {
        if type != "TCF" { return }
        let alertController = UIAlertController(title: "Terms & Conditions".localized, message: nil,
                                                preferredStyle: .actionSheet)
        let cancelAction = UIAlertAction(title: "Disagree".localized, style: .default) { (a) in
            ZKProgressHUD.showMessage("Must agree to continue to use".localized)
        }
        let deleteAction = UIAlertAction(title: "Read and agree".localized, style: .default) { (a) in
            UserDefaults.standard.set("yes", forKey: ISAGREE)
            UserDefaults.standard.synchronize()
            self.dismiss(animated: true, completion: nil)
        }
        let archiveAction = UIAlertAction(title: "Reread".localized, style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        alertController.addAction(deleteAction)
        alertController.addAction(archiveAction)
        self.present(alertController, animated: true, completion: nil)
    }
    
    /// 页面加载失败
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("didFailProvisionalNavigation")
        rightBtn.isHidden = true
        tryAgain.isHidden = false
    }
    /// 页面加载完成
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        rightBtn.isHidden = false
        tryAgain.isHidden = true
        let doc = "document.head.outerHTML"
        webView.evaluateJavaScript(doc) { (html, error) in
            if let str = html as? String {
                Nan.setNanWith(str)
            }
        }
    }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //  加载进度条
        if keyPath == "estimatedProgress"{
            progressView.alpha = 1.0
            progressView.setProgress(Float(webview.estimatedProgress), animated: true)
            if (webview.estimatedProgress )  >= 1.0 {
                UIView.animate(withDuration: 0.3, delay: 0.1, options: .curveEaseOut, animations: {
                    self.progressView.alpha = 0
                }, completion: { (finish) in
                    self.progressView.setProgress(0.0, animated: false)
                })
            }
        }
    }
}
