//
//  SessionResponseViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import TunnelServices

class SessionResponseViewController: UIViewController {

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
        
        let rspView = SessionItemView(title: "Response line".localized, content: "\(session.rspHttpVersion ?? "") \(session.state ?? "") \(session.rspMessage ?? "")")
        rspView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: rspView.itemHeight)
        rspView.didClickHandle = { text in
            VisualActivityViewController.share(text: text, on: self)
        }
        scrollView.addSubview(rspView)
        offY = offY + rspView.frame.height
        
        if session.rspBody != "" {
            let filePath = "\(session.fileFolder ?? "error")/\(session.rspBody)"
            let nfilePath = "\(MitmService.getStoreFolder())\(filePath)"
            if FileManager.default.fileExists(atPath: nfilePath) {
                let rspBodyView = SessionBodyView(title: "Response body".localized, path: filePath, type: session.rspType , size: 300000)
                rspBodyView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: rspBodyView.itemHeight)
                scrollView.addSubview(rspBodyView)
                offY = offY + rspBodyView.frame.height
                rspBodyView.isUserInteractionEnabled = true
                rspBodyView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bodyDidClick)))
            }
        }
        
        let rspHeadView = SessionHeadView(title: "Response header".localized, headJson: session.rspHeads ?? "")
        rspHeadView.didClickHandle = {
            self.navigationController?.pushViewController(SessionHeaderViewController(session: self.session, isReq: false), animated: true)
        }
        rspHeadView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: rspHeadView.itemHeight)
        scrollView.addSubview(rspHeadView)
        offY = offY + rspHeadView.frame.height
        
        scrollView.contentSize = CGSize(width: 0, height: offY)
    }

    @objc func bodyDidClick(){
        navigationController?.pushViewController(SessionBodyViewController(session: session, showRSP: true), animated: true)
    }
}
