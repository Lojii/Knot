//
//  SessionRequestViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionRequestViewController: UIViewController {
    
    var session:Session
    lazy var scrollView: UIScrollView = {
        let scrollViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let scrollView = UIScrollView(frame: scrollViewFrame)
        return scrollView
    }()
    
    init(_ session:Session) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(scrollView)
        setUI()
    }
    
    func setUI(){
        var offY:CGFloat = 0
        var urlView = SessionItemView(title: "Link".localized, content: "\(session.uri ?? "")")
        if let uri = session.uri,uri.starts(with: "/") {
            urlView = SessionItemView(title: "Link".localized, content: session.getFullUrl())
        }
        urlView.didClickHandle = { text in
            if let url = URL(string: text){
                VisualActivityViewController.share(url: url, on: self)
            }else{
                VisualActivityViewController.share(text: text, on: self)
            }
        }
        
        urlView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: urlView.itemHeight)
        scrollView.addSubview(urlView)
        offY = offY + urlView.frame.height
        
        if session.reqBody != "" {
            let filePath = "\(session.fileFolder ?? "error")/\(session.reqBody)"
            let nfilePath = "\(MitmService.getStoreFolder())\(filePath)"
            if FileManager.default.fileExists(atPath: nfilePath) {
                let reqBodyView = SessionBodyView(title: "Request body".localized, path: filePath, type: session.reqType, size: 300000)
                reqBodyView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: reqBodyView.itemHeight)
                scrollView.addSubview(reqBodyView)
                offY = offY + reqBodyView.frame.height
                reqBodyView.isUserInteractionEnabled = true
                reqBodyView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bodyDidClick)))
            }
        }
        
        let reqHeadView = SessionHeadView(title: "Request header".localized, headJson: session.reqHeads ?? "")
        reqHeadView.didClickHandle = {
            self.navigationController?.pushViewController(SessionHeaderViewController(session: self.session, isReq: true), animated: true)
        }
        reqHeadView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: reqHeadView.itemHeight)
        scrollView.addSubview(reqHeadView)
        offY = offY + reqHeadView.frame.height
        
        let reqView = SessionItemView(title: "Request line".localized, content: session.reqLine ?? "")
        reqView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: reqView.itemHeight)
        reqView.didClickHandle = { text in
            VisualActivityViewController.share(text: text, on: self)
        }
        scrollView.addSubview(reqView)
        offY = offY + reqView.frame.height
        
        scrollView.contentSize = CGSize(width: 0, height: offY)
    }
    
    @objc func bodyDidClick(){
        navigationController?.pushViewController(SessionBodyViewController(session: session, showRSP: false), animated: true)
    }
}
