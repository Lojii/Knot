//
//  CellPopViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/28.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices


protocol CellPopViewControllerDelegate: class {
    func cellPopViewDidFocuse(focuseOption:SearchOption)    // Focus
    func cellPopViewOutput(session:Session,type:OutputType)     // 导出
    func cellPopViewCollect(session:Session)                // 收藏
}

class CellPopViewController: UIViewController,PopupContentViewController {
    
    let ignoreKey = ["A-IM","Accept","Accept-Additions","Accept-Charset","Accept-Datetime","Accept-Encoding","Accept-Features","Accept-Language","Accept-Patch","Accept-Post","Accept-Ranges","Age","Allow","ALPN","Alt-Svc","Alt-Used","Alternates","Apply-To-Redirect-Ref","Authentication-Control","Authentication-Info","Authorization","C-Ext","C-Man","C-Opt","C-PEP","C-PEP-Info","Cache-Control","CalDAV-Timezones","Close","Connection","Content-Base","Content-Disposition","Content-Encoding","Content-ID","Content-Language","Content-Length","Content-Location","Content-MD5","Content-Range","Content-Script-Type","Content-Security-Policy","Content-Style-Type","Content-Type","Content-Version","DASL","DAV","Date","Default-Style","Delta-Base","Depth","Derived-From","Destination","Differential-ID","Digest","ETag","Expect","Expires","Ext","Forwarded","From","GetProfile","Hobareg","Host","HTTP2-Settings","IM","If","If-Match","If-Modified-Since","If-None-Match","If-Range","If-Schedule-Tag-Match","If-Unmodified-Since","Keep-Alive","Label","Last-Modified","Link","Location","Lock-Token","Man","Max-Forwards","Memento-Datetime","Meter","MIME-Version","Negotiate","Opt","Optional-WWW-Authenticate","Ordering-Type","Origin","Overwrite","P3P","PEP","PICS-Label","Pep-Info","Position","Pragma","Prefer","Preference-Applied","ProfileObject","Protocol","Protocol-Info","Protocol-Query","Protocol-Request","Proxy-Authenticate","Proxy-Authentication-Info","Proxy-Authorization","Proxy-Features","Proxy-Instruction","Public","Public-Key-Pins","Public-Key-Pins-Report-Only","Range","Redirect-Ref","Referer","Retry-After","Safe","Schedule-Reply","Schedule-Tag","Sec-WebSocket-Accept","Sec-WebSocket-Extensions","Sec-WebSocket-Key","Sec-WebSocket-Protocol","Sec-WebSocket-Version","Security-Scheme","Server","SetProfile","SLUG","SoapAction","Status-URI","Strict-Transport-Security","Surrogate-Capability","Surrogate-Control","TCN","TE","Timeout","Topic","Trailer","Transfer-Encoding","TTL","Urgency","URI","Upgrade","User-Agent","Variant-Vary","Vary","Via","WWW-Authenticate","Want-Digest","Warning","X-Content-Type-Options","X-Frame-Options","X-XSS-Protection","Access-Control","Access-Control-Allow-Credentials","Access-Control-Allow-Headers","Access-Control-Allow-Methods","Access-Control-Allow-Origin","Access-Control-Expose-Headers","Access-Control-Max-Age","Access-Control-Request-Method","Access-Control-Request-Headers","Compliance","Content-Transfer-Encoding","Cost","EDIINT-Features","Message-ID","Method-Check","Method-Check-Expires","Non-Compliance","Optional","Referer-Root","Resolution-Hint","Resolver-Location","SubOK","Subst","Title","UA-Color","UA-Media","UA-Pixels","UA-Resolution","UA-Windowpixels","Version","X-Device-Accept","X-Device-Accept-Charset","X-Device-Accept-Encoding","X-Device-Accept-Language","X-Device-User-Agent",
                     "X-Requested-With"]
    var session:Session
    var focusOption:SearchOption
    var copyOptions:SearchOption
    var closeHandler: (() -> Void)?
    
    weak var delegate:CellPopViewControllerDelegate?
    var focusChange = false
    let cornerRadius:CGFloat = 12
    var viewHeight:CGFloat = 0
    let spacing:CGFloat = 8
    let viewWidth:CGFloat = SCREENWIDTH - 8 * 2//LRSpacing
    let titleHeight:CGFloat = 50  // 57
    let scrollViewMaxHeight:CGFloat = SCREENHEIGHT - STATUSBARHEIGHT - XBOTTOMHEIGHT - 5 * 50 - 20
    
    var cancelBtn:UIButton = UIButton()
    var focusBtn:UIButton = UIButton()
    
    var scrollView = UIScrollView()
    
    init(session:Session, focusOption:SearchOption) {
        self.session = session
        self.focusOption = focusOption
        self.copyOptions = focusOption.getACopy()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
    }
    
    func setupUI(){
        let topView = UIView()
        topView.backgroundColor = ColorF
        topView.layer.cornerRadius = cornerRadius
        topView.clipsToBounds = true
        
        
        let focusTitleLable = UILabel(frame: CGRect(x: 0, y: 0, width: viewWidth, height: titleHeight))
        focusTitleLable.text = "Focus"
        focusTitleLable.font = Font18
        focusTitleLable.textColor = ColorA
        focusTitleLable.textAlignment = .center
        focusTitleLable.backgroundColor = .white
        topView.addSubview(focusTitleLable)
        setupScrollView()
        topView.addSubview(scrollView)
        
        let outUrlBtn = setButton(title: "Export link".localized, y: scrollView.frame.maxY + 1, action: #selector(outputUrl))
        topView.addSubview(outUrlBtn)
        let outcUrlBtn = setButton(title: "Export cURL".localized, y: outUrlBtn.frame.maxY + 1, action: #selector(outputcUrl))
        topView.addSubview(outcUrlBtn)
        let outHarBtn = setButton(title: "Export HTTP Archive (.har)".localized, y: outcUrlBtn.frame.maxY + 1, action: #selector(outputHar))
        topView.addSubview(outHarBtn)
        topView.frame = CGRect(x: spacing, y: 0, width: viewWidth, height: outHarBtn.frame.maxY)
        view.addSubview(topView)
        
//        let outRspBtn = setButton(title: "导出响应体", y: outHarBtn.frame.maxY + 1, action: #selector(outputHar))
//        let outImgBtn = setButton(title: "导出图片", y: outRspBtn.frame.maxY + 1, action: #selector(outputHar))
        
        let bottomView = UIView()
        bottomView.backgroundColor = ColorR
        bottomView.layer.cornerRadius = cornerRadius
        bottomView.clipsToBounds = true
        
        cancelBtn = setButton(title: "Cancel".localized, y: 0, action: #selector(cancel))
        cancelBtn.setTitleColor(ColorB, for: .highlighted)
        cancelBtn.setBackgroundImage(UIImage.renderImageWithColor(ColorF, size: CGSize(width: SCREENWIDTH, height: 100)), for: .highlighted)
        bottomView.addSubview(cancelBtn)
        
        focusBtn = setButton(title: "Focus", y: 0, action: #selector(focus))
        focusBtn.frame = CGRect(x: viewWidth, y: 0, width: viewWidth, height: titleHeight)
        focusBtn.setTitleColor(.white, for: .normal)
        focusBtn.backgroundColor = ColorSY
        bottomView.addSubview(focusBtn)
        bottomView.frame = CGRect(x: spacing, y: topView.frame.maxY + spacing, width: viewWidth, height: cancelBtn.frame.maxY)
        view.addSubview(bottomView)
        
        viewHeight = bottomView.frame.maxY + spacing + XBOTTOMHEIGHT
    }
    
    func setButton(title:String,y:CGFloat, action: Selector) -> UIButton{
        let btn = UIButton(frame: CGRect(x: 0, y: y, width: viewWidth, height: titleHeight))
        btn.setTitleColor(ColorA, for: .normal)
        btn.setTitle(title, for: .normal)
        btn.backgroundColor = .white
        btn.titleLabel?.font = Font18
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.setTitleColor(ColorB, for: .highlighted)
        btn.setBackgroundImage(UIImage.renderImageWithColor(ColorF, size: CGSize(width: SCREENWIDTH, height: 100)), for: .highlighted)
        return btn
    }
    
    func setupScrollView(){
        scrollView.frame = CGRect(x: 0, y: titleHeight, width: viewWidth, height: 100)
        scrollView.backgroundColor = .white
        
        
        // 从session中获取关键信息
        var items = [[String:[[SearchKey:[String]]]]]()
        // general
        var general = [[SearchKey:[String]]]()
        if let methods = session.methods { general.append([.methods : [methods]]) }
        let type = session.rspType
        if !type.isEmpty() { general.append([.rspType : [type]]) }
        if let state = session.state { general.append([.state : [state]]) }
        if let schemes = session.schemes { general.append([.schemes : [schemes]]) }
        if let target = session.target { general.append([.target : [target]]) }
        if general.count > 0 { items.append(["General":general]) }  //*********************
        // ip/host
        var iphost = [[SearchKey:[String]]]()
        if let host = session.host { iphost.append([.host : [host]]) }
        if let local = session.localAddress?.components(separatedBy: ":").first,local != "" { iphost.append([.localAddress : [local]])}
        if iphost.count > 0 { items.append(["IP/Host":iphost]) }  //*********************
        // uri/api
        var uriapi = [[SearchKey:[String]]]()
        if let uri = session.uri,uri.count > 0 {// www.xxx.com/xxx/xxx/xxx?xx=xx&xx=xx
            if let host = session.host {
                if let s1 = uri.components(separatedBy: host).last {    // /xxx/xxx/xxx?xx=xx&xx=xx
                    let s1s = s1.components(separatedBy: "?")
                    if let s2 = s1s.first { // /xxx/xxx/xxx
                        let fistCharIsX = (s2.first == "/")
                        let s2s = s2.components(separatedBy: "/")  //  xxx xxx xxx
                        var values = [String]()
                        for index in 0..<s2s.count{
                            let value = s2s[index]
                            if value.isEmpty { continue }
                            if index == 0 , !fistCharIsX {
                                values.append(value)
                            }else{
                                values.append("/\(value)")
                            }
                        }
                        if values.count > 0{ uriapi.append([.uri : values]) }
                    }
                    if uriapi.count > 0{ items.append(["Uir":uriapi]) }  //*********************
                    
                    var uriparams = [[SearchKey:[String]]]()
                    if s1s.count >= 2 {
                        let s2 = s1s[1] // xx=xx&xx=xx
                        let s2s = s2.components(separatedBy: "&")  // xx=xx xx=xx
                        var vs = [String]()
                        for i in 0..<s2s.count {
                            let s3 = s2s[i]
                            let s3s = s3.components(separatedBy: "=")
                            if s3s.count == 2 {
                                vs.append(s3s[0])
                                vs.append(s3s[1])
                            }
                        }
                        if vs.count > 0{
                            uriparams.append([SearchKey.uri : vs])
                            items.append(["Parameter": uriparams])  //*********************
                        }
                    }
                }
            }
        }
        // reqHead
        if let reqHeads = session.reqHeads {
            let headDic = Dictionary<String, String>.fromJson(reqHeads)
            var values = [String]()
            for dic in headDic {
                if !ignoreKey.contains(dic.key) {
                    values.append(dic.key)
                    values.append(dic.value)
                }
            }
            if values.count > 0{
                items.append(["Head" : [[SearchKey.reqHeads : values]]])  //*********************
            }
        }
        // rspHead
//        if let rspHeads = session.rspHeads {
//            let headDic = Dictionary<String, String>.fromJson(rspHeads)
//            var values = [String]()
//            for dic in headDic {
//                if !ignoreKey.contains(dic.key) {
//                    values.append(dic.key)
//                    values.append(dic.value)
//                }
//            }
//            if values.count > 0{
//                items.append(["RspHead" : [[SearchKey.rspHeads : values]]])  //*********************
//            }
//        }
//        print("items:\(items)")
        
        // 将关键信息填充到scrollView
        if items.count <= 0 {
            scrollView.frame = CGRect(x: 0, y: titleHeight, width: viewWidth, height: 0)
            return
        }
        var offX:CGFloat = LRSpacing
        var offY:CGFloat = 5
        let width = SCREENWIDTH - LRSpacing
        let btnH:CGFloat = 25
        let btnSpacingH:CGFloat = 8 // 水平间隔
        let btnSpacingV:CGFloat = 8 // 垂直间隔
        let btnFont = Font13
        let titleH:CGFloat = 30
        
        for item in items {
            if let title = item.keys.first, let values = item.values.first {
                if title == "General" { // "General", "IP/Host", "Uir", "Parameter", "Head"
                    
                }
                let titleLabel = UILabel(frame: CGRect(x: offX, y: offY, width: width - LRSpacing * 2, height: titleH))
                titleLabel.text = title
                titleLabel.textColor = ColorB
                titleLabel.font = Font14
                titleLabel.textAlignment = .left
                scrollView.addSubview(titleLabel)
                offY = offY + titleH
                for sm in values {
                    if let key = sm.keys.first, let strs = sm.values.first {
                        for v in strs {
                            var btnW = v.textWidth(font: btnFont) + 16
                            if btnW > width - LRSpacing * 2 { btnW = width - LRSpacing * 2 }
                            if btnW + offX > width {
                                offY = offY + btnH + btnSpacingV
                                offX = LRSpacing
                            }
                            let btn = UIButton()
                            btn.setTitle(v, for: .normal)
                            btn.titleLabel?.font = btnFont
                            btn.setTitleColor(ColorB, for: .normal)
                            btn.setTitleColor(.white, for: .selected)
                            btn.setTitle("\(key)", for: .disabled)
                            btn.setBackgroundImage(UIImage.renderImageWithColor(ColorSG, size: CGSize(width: 1, height: 1)), for: .selected)
                            btn.setBackgroundImage(UIImage.renderImageWithColor(ColorF, size: CGSize(width: 1, height: 1)), for: .normal)
                            btn.frame = CGRect(x: offX, y: offY, width: btnW, height: btnH)
                            btn.isSelected = focusOption.contains(key: key, value: v)
                            btn.addTarget(self, action: #selector(focuseBtnDidClick(btn:)), for: .touchUpInside)
                            scrollView.addSubview(btn)
                            offX = offX + btnW + btnSpacingH
                        }
                    }
                }
                offY = offY + btnH + btnSpacingV
                offX = LRSpacing
            }
        }
        let scrollViewHeight = offY > scrollViewMaxHeight ? scrollViewMaxHeight : offY
        scrollView.frame = CGRect(x: 0, y: titleHeight, width: viewWidth, height: scrollViewHeight)
        scrollView.contentSize = CGSize(width: 0, height: offY)
    }
    
    func showFocusBtn(){
        let cFrame = cancelBtn.frame
        let fFrame = focusBtn.frame
        UIView.animate(withDuration: 0.25) {
            self.cancelBtn.frame = CGRect(x: cFrame.origin.x, y: cFrame.origin.y, width: cFrame.size.width / 2, height: cFrame.size.height)
            self.focusBtn.frame = CGRect(x: fFrame.size.width / 2, y: fFrame.origin.y, width: fFrame.size.width / 2, height: fFrame.size.height)
        }
    }
    
    @objc func focuseBtnDidClick(btn:UIButton){
        btn.isSelected = !btn.isSelected
        if let key = btn.title(for: .disabled), let value = btn.title(for: .normal){
            if let searchKey = SearchKey(rawValue: key) {
                if btn.isSelected {
                    focusOption.addMap(key: searchKey, values: [value])
                }else{
                    focusOption.delete(key: searchKey, values: [value])
                }
            }
        }
        if !focusChange {
            focusChange = true
            showFocusBtn()
        }
    }
    
    @objc func outputUrl(){
        delegate?.cellPopViewOutput(session: session, type: .URL)
    }
    @objc func outputcUrl(){
        delegate?.cellPopViewOutput(session: session, type: .CURL)
    }
    @objc func outputHar(){
        delegate?.cellPopViewOutput(session: session, type: .HAR)
    }
    @objc func cancel(){
        closeHandler?()
    }
    @objc func focus(){
        delegate?.cellPopViewDidFocuse(focuseOption: focusOption)
        closeHandler?()
    }
 
    func sizeForPopup(_ popupController: PopupController, size: CGSize, showingKeyboard: Bool) -> CGSize {
        return CGSize(width: SCREENWIDTH, height: viewHeight)
    }
}
