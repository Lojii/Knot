//
//  SessionHeaderViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/6.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan
import SnapKit

class SessionHeaderViewController: BaseViewController {
    
    var session:Session
    var isReq:Bool = true
    
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
    
    init(session:Session,isReq:Bool = true) {
        self.session = session
        self.isReq = isReq
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        session.parse { reqLinePath, reqHeadPath, reqBodyPath, rspLinePath, rspHeadPath, rspBodyPath in
            self.setUI()
        }
    }
    
    override func viewDidLayoutSubviews(){
       super.viewDidLayoutSubviews()
       scrollView.contentSize = CGSize(width: stackView.frame.width, height: stackView.frame.height + 34)
    }
    
    func setUI() -> Void {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        
        navBar.titleLable.text = isReq ? "Request header".localized : "Response header".localized
        let moreImg = UIImage(named: "more1")?.imageWithTintColor(color: ColorM)
        rightBtn.setImage(moreImg, for: .normal)
        rightBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: LRSpacing)
        rightBtn.imageView?.contentMode = .scaleAspectFit
        addList()
    }
    
    func addList(){
        if let headDic = session.head(isReq) {
            var kvs = [[String:String]]()
            for kv in headDic { kvs.append([kv.key:kv.value]) }
            kvs.sort { (kv1, kv2) -> Bool in
                return kv1.keys.first!.localizedCompare(kv2.keys.first!) == ComparisonResult.orderedAscending
            }
            var lastV:UIView?
            for dic in kvs {
                let itemView = SessionItemView(title: dic.keys.first ?? "", content: dic.values.first ?? "", true)
                itemView.didClickHandle = { text in
                    KnotPurchase.check(.HappyKnot) { res in
                        if(res){
                            VisualActivityViewController.share(text: text, on: self)
                        }else{
                            ZKProgressHUD.showError("Purchase failed".localized)
                        }
                    }
                }
                stackView.addArrangedSubview(itemView)
                lastV = itemView
            }
            stackView.snp.makeConstraints { make in
                make.top.equalTo(scrollView.snp_top)
                make.left.equalTo(scrollView.snp_left)
                make.width.equalTo(SCREENWIDTH)
                if lastV != nil {
                    make.bottom.equalTo(lastV!.snp_bottom)
                }
            }
        }
    }
    
    override func rightBtnClick() {
        PopViewController.show(titles: ["Export Json".localized,"Export key:value".localized], viewController: self) { (index) in
            guard let headDic = self.session.head(self.isReq) else {
                ZKProgressHUD.showError("no headers")
                return
            }
            if index == 0 {
                if let data = try? JSONSerialization.data(withJSONObject: headDic, options: []), let json = String(data: data, encoding: .utf8) {
                    KnotPurchase.check(.HappyKnot) { res in
                        if(res){
                            VisualActivityViewController.share(text: json, on: self, "json")
                        }
                    }
                }
            }else{
                var text = ""
                for kv in headDic {
                    text.append("\(kv.key):\(kv.value)\r\n")
                }
                KnotPurchase.check(.HappyKnot) { res in
                    if(res){
                        VisualActivityViewController.share(text: text, on: self)
                    }
                }
            }
        }
    }
}
