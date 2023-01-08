//
//  WebVC.swift
//  NIO2022
//
//  Created by LiuJie on 2022/3/7.
//

import Foundation
import WebKit

class WebVC: UIViewController, WKNavigationDelegate {
    
    var webView: WKWebView!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        let url = URL(string: "https://www.baidu.com/")
//        let url = URL(string: "https://cn.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1")
        let url = URL(string: "http://api.asilu.com/php/web-info.php")
//        let url = URL(string: "https://www.douyin.com/")
//        let url = URL(string: "https://www.zhihu.com/")
//        let url = URL(string: "https://www.csdn.net/")
//        let url = URL(string: "https://www.jianshu.com/")
//        let url = URL(string: "https://query.asilu.com/news/oschina-news")
//        let url = URL(string: "https://top.baidu.com/board?platform=pc&sa=pcindex_a_right")
//        let url = URL(string: "https://top.baidu.com")
//        let url = URL(string: "https://vd3.bdstatic.com/mda-mf1iqic68uk3j47t/hd/cae_h264_nowatermark/1622640378240139723/mda-mf1iqic68uk3j47t.mp4")
//        let url = URL(string: "https://dss0.bdstatic.com/5aV1bjqh_Q23odCf/static/superman/amd_modules/@baidu/aging-tools-pc-1e5afe8bdf.js")
//        let url = URL(string: "http://pic.rmb.bdstatic.com/90a3cc56048cc77b55e93b3d1ba00c0b.jpeg?x-bce-process=image/resize,m_lfit,w_200,h_200&autime=2833")
//
        let request = URLRequest(url: url!)
//        HttpProxyProtocol.webKitSupport = true
//        HttpProxyProtocol.start(proxyConfig: (host, port))
        
        let fullWH = UIScreen.main.bounds.size
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: fullWH.width, height: fullWH.height))//UIWebView(frame: CGRect(x: 0, y: 0, width: fullWH.width, height: fullWH.height))
        webView.backgroundColor = .white
//        webView.navigationDelegate = self
        view.addSubview(webView)

        webView.load(request)
    }
}
