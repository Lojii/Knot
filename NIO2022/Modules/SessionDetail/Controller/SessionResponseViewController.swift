//
//  SessionResponseViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/14.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan

class SessionResponseViewController: UIViewController {

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

        if let line = session.line(false) {
            let rspView = SessionItemView(title: "Response line".localized, content: line)
            rspView.didClickHandle = { text in
                KnotPurchase.check(.HappyKnot) { res in
                    if(res){
                        VisualActivityViewController.share(text: text, on: self)
                    }
                }
            }
            stackView.addArrangedSubview(rspView)
            lastV = rspView
        }
        
        if let bodyPath = session.body(false) {
            let rspBodyView = SessionBodyView(title: "Response body".localized, path: bodyPath, type: session.suffix , size: 300000)
            rspBodyView.isUserInteractionEnabled = true
            rspBodyView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bodyDidClick)))
            stackView.addArrangedSubview(rspBodyView)
            lastV = rspBodyView
        }

        if let heads = session.head(false) {
            let rspHeadView = SessionHeadView(title: "Response header".localized, heads: heads)
            rspHeadView.didClickHandle = {
                self.navigationController?.pushViewController(SessionHeaderViewController(session: self.session, isReq: false), animated: true)
            }
            stackView.addArrangedSubview(rspHeadView)
            lastV = rspHeadView
        }
        
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
        navigationController?.pushViewController(SessionBodyViewController(session: session, showRSP: true), animated: true)
    }
}
