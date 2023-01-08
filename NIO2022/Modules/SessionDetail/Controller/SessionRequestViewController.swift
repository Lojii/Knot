//
//  SessionRequestViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan
import SnapKit

class SessionRequestViewController: UIViewController {
    
    var session:Session
    lazy var scrollView: UIScrollView = {
        let scrollViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let scrollView = UIScrollView(frame: scrollViewFrame)
        return scrollView
    }()
    
    lazy var stackView:UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        return stackView
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
        scrollView.addSubview(stackView)
        setUI()
    }
    
    override func viewDidLayoutSubviews(){
       super.viewDidLayoutSubviews()
       scrollView.contentSize = CGSize(width: stackView.frame.width, height: stackView.frame.height + 34)
    }
    
    func setUI(){
        var lastV:UIView?
        let urlView = SessionItemView(title: "Link".localized, content: session.fullUrl())
        urlView.didClickHandle = { text in
            KnotPurchase.check(.HappyKnot) { res in
                if(res){
                    if let url = URL(string: text){
                        VisualActivityViewController.share(url: url, on: self)
                    }else{
                        VisualActivityViewController.share(text: text, on: self)
                    }
                }
            }
        }
        stackView.addArrangedSubview(urlView)
        lastV = urlView
        if let reqBodyPath = session.body() {
            let reqBodyView = SessionBodyView(title: "Request body".localized, path: reqBodyPath, type: session.req_content_type, size: 300000)
            stackView.addArrangedSubview(reqBodyView)
            lastV = reqBodyView
            reqBodyView.isUserInteractionEnabled = true
            reqBodyView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bodyDidClick)))
        }
//
        if let head = session.head() {
            let reqHeadView = SessionHeadView(title: "Request header".localized, heads:head)
            reqHeadView.didClickHandle = {
                self.navigationController?.pushViewController(SessionHeaderViewController(session: self.session, isReq: true), animated: true)
            }
            stackView.addArrangedSubview(reqHeadView)
            lastV = reqHeadView
        }
//
        if let line = session.line() {
            let reqView = SessionItemView(title: "Request line".localized, content: line)
            reqView.didClickHandle = { text in
                KnotPurchase.check(.HappyKnot) { res in
                    if(res){
                        VisualActivityViewController.share(text: text, on: self)
                    }
                }
            }
            stackView.addArrangedSubview(reqView)
            lastV = reqView
        }
//
        stackView.snp.makeConstraints { make in
            make.top.equalTo(scrollView.snp_top)
            make.left.equalTo(scrollView.snp_left)
            make.right.equalTo(scrollView.snp_right)
            if lastV != nil {
                make.bottom.equalTo(lastV!.snp_bottom)
            }
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    @objc func bodyDidClick(){
        navigationController?.pushViewController(SessionBodyViewController(session: session, showRSP: false), animated: true)
    }
}
