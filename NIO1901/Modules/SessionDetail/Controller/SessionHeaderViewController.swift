//
//  SessionHeaderViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/6.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionHeaderViewController: BaseViewController {
    
    var session:Session
    var isReq:Bool = true
    
    lazy var scrollView: UIScrollView = {
        let scrollViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let scrollView = UIScrollView(frame: scrollViewFrame)
        return scrollView
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
        setUI()
    }
    
    func setUI() -> Void {
        view.addSubview(scrollView)
        navBar.titleLable.text = isReq ? "Request header".localized : "Response header".localized
        let moreImg = UIImage(named: "more1")?.imageWithTintColor(color: ColorM)
        rightBtn.setImage(moreImg, for: .normal)
        rightBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: LRSpacing)
        rightBtn.imageView?.contentMode = .scaleAspectFit
        addList()
    }
    
    func addList(){
        guard let headerJson = isReq ? session.reqHeads : session.rspHeads else { return }
        let headDic = [String:String].fromJson(headerJson)
        var offY:CGFloat = 0
        var kvs = [[String:String]]()
        for kv in headDic { kvs.append([kv.key:kv.value]) }
        kvs.sort { (kv1, kv2) -> Bool in
            return kv1.keys.first!.localizedCompare(kv2.keys.first!) == ComparisonResult.orderedAscending
        }
        for dic in kvs {
            let itemView = SessionItemView(title: dic.keys.first ?? "", content: dic.values.first ?? "", true)
            itemView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: itemView.itemHeight)
            itemView.didClickHandle = { text in
                VisualActivityViewController.share(text: text, on: self)
            }
            offY = itemView.frame.maxY
            scrollView.addSubview(itemView)
        }
        scrollView.contentSize = CGSize(width: 0, height: offY)
    }
    
    override func rightBtnClick() {
        PopViewController.show(titles: ["Export Json".localized,"Export key:value".localized], viewController: self) { (index) in
            guard let headerJson = self.isReq ? self.session.reqHeads : self.session.rspHeads else {
                ZKProgressHUD.showError("no headers")
                return
            }
            if index == 0 {
                VisualActivityViewController.share(text: headerJson, on: self, "json")
            }else{
                let dic = [String:String].fromJson(headerJson)
                var text = ""
                for kv in dic {
                    text.append("\(kv.key): \(kv.value)\n")
                }
                VisualActivityViewController.share(text: text, on: self)
            }
        }
    }
}
