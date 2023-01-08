//
//  SessionCell.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/24.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
//import TangramKit
import YYImage
import YYWebImage
import NIOMan
import SnapKit

protocol SessionCellDelegate: class {
    func moreBtnDidClick(session:Session?)
    func sessionCellSelectedChange(session:Session?,selected: Bool,indexPath: IndexPath?)
}

class SessionCell: UITableViewCell {

    weak var delegate:SessionCellDelegate?
    var indexPath: IndexPath?
    var tap:UITapGestureRecognizer?
    
    var uriLabel:UILabel!  // /xxx/xx.xx?x=x&xxx=x
    var hostLabel:UILabel!      // xxx.xxx
    var methodsLabel:UILabel!   // get\post...
    var timeLabel:UILabel!      // 04-23 09:34:54.235
    var remoteAddress:UILabel!  // 87.234.12.6
    var localAddress:UILabel!   // 127.0.0.1:8734 \ 192.168.1.43:8735
    var typeLabel:UILabel!      // .gif\.js\.css
    var stateLabel:UILabel!     // 200\404\430
    var targetLabel:UILabel!    // Safari\qq
    var isHttpsLabel: UILabel!  // Http\Https
    var stateLine:UIView!
    
    var previewImage:YYAnimatedImageView!// 预览
    var moreBtn:UIButton!       // 更多
    var isCollect:UIImageView!  // 是否收藏
    
    var upLabel:UILabel!      // 102.32KB
    var upImage:UIImageView!
    var downLabel:UILabel!      // 2.32MB
    var downImage:UIImageView!
    
    let moreBtnW:CGFloat = 25
    let moreBtnH:CGFloat = 30
    
    var lineView:UIView!
    
//    var disableView:UIView
    lazy var disableView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(redValue: 0, green: 0, blue: 0, alpha: 0.5)
        contentView.addSubview(v)
        v.snp.makeConstraints { m in
            m.top.left.right.bottom.equalToSuperview()
        }
        return v
    }()
    var isDisable:Bool = true
    var disable: Bool {
        get {
            return isDisable
        }
        set {
            disableView.isHidden = !newValue
            isDisable = newValue
        }
    }
    
    private var _session:SessionItem?
    var session:SessionItem?{
        set{
            _session = newValue
            resetData()
        }
        get{
            return _session
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        initUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func initUI() -> Void {
        uriLabel = UILabel.initWith(color: ColorM, font: Font14, text: "/")
        uriLabel.numberOfLines = 4
        uriLabel.lineBreakMode = .byCharWrapping
//        uriLabel.lineBreakMode
        
        methodsLabel = UILabel.initWith(color: ColorA, font: Font14, text: "GET")   // get\post...
        typeLabel = UILabel.initWith(color: ColorA, font: Font14, text: "gif")      // .gif\.js\.css
        stateLabel = UILabel.initWith(color: ColorA, font: Font14, text: "200")     // 200\404\430
        hostLabel = UILabel.initWith(color: ColorA, font: Font14, text: "xxx.xxx.xxx")      // xxx.xxx
        
        targetLabel = UILabel.initWith(color: ColorB, font: Font13, text: "Safari")    // Safari\qq
        localAddress = UILabel.initWith(color: ColorB, font: Font13, text: "127.0.0.1:8734")   // 127.0.0.1 = 8734 \ 192.168.1.43 = 8735
        remoteAddress = UILabel.initWith(color: ColorB, font: Font13, text: "87.234.12.6")  // 87.234.12.6
        
        timeLabel = UILabel.initWith(color: ColorC, font: Font12, text: "09:34:54.235")      // 04-23 09:34:54.235
        upLabel = UILabel.initWith(color: ColorC, font: Font12, text: "102.32KB")
        downLabel = UILabel.initWith(color: ColorC, font: Font12, text: "2.32MB")
        
        upImage = UIImageView(image: UIImage(named: "arrowup"))
        upImage.contentMode = .scaleAspectFit
        downImage = UIImageView(image: UIImage(named: "arrowdown"))
        downImage.contentMode = .scaleAspectFit
        stateLine = UIView()
        stateLine.layer.cornerRadius = 2
        stateLine.clipsToBounds = true
        
        moreBtn = UIButton()
        moreBtn.setImage(UIImage(named: "more1")?.imageWithTintColor(color: ColorC), for: .normal)
        moreBtn.contentMode = .scaleAspectFit
        moreBtn.addTarget(self, action: #selector(moreDidClick), for: .touchUpInside)
//        moreBtn.backgroundColor = ColorM
        
        previewImage = YYAnimatedImageView()
        previewImage.backgroundColor = ColorE
        previewImage.contentMode = .scaleAspectFit//.scaleAspectFill
        previewImage.clipsToBounds = true
        previewImage.setupForImageViewer(.black)
        
        lineView = UIView()
        lineView.backgroundColor = ColorE
        
        contentView.addSubview(uriLabel)
        contentView.addSubview(methodsLabel)
        contentView.addSubview(typeLabel)
        contentView.addSubview(stateLabel)
        contentView.addSubview(hostLabel)
        contentView.addSubview(targetLabel)
        contentView.addSubview(localAddress)
        contentView.addSubview(remoteAddress)
        contentView.addSubview(timeLabel)
        contentView.addSubview(upLabel)
        contentView.addSubview(downLabel)
        contentView.addSubview(upImage)
        contentView.addSubview(downImage)
        contentView.addSubview(stateLine)
        contentView.addSubview(previewImage)
        contentView.addSubview(lineView)
        contentView.addSubview(moreBtn)
//        layoutIfNeeded()
        resetUI()
    }
    
    func resetUI(){
        guard let s = session else {
            return
        }
        //
        var x = LRSpacing
        var y = SessionItem.TopSpacint
        uriLabel.frame = CGRect(x: x, y: y, width: s.uriW, height: s.uriH)
        y = uriLabel.frame.maxY
        //
        methodsLabel.frame = CGRect(x: x, y: y, width: s.methodsW, height: s.methodsH)
        x = methodsLabel.frame.maxX + 2
        let type = s.type//s.session.rsp_content_type
        if type != "" {
            typeLabel.frame = CGRect(x: x, y: y, width: s.typeW, height: s.methodsH)
            x = typeLabel.frame.maxX + 2
        }
//        x = x + 2
        stateLabel.frame = CGRect(x: x, y: y, width: s.stateW, height: s.methodsH)
        x = stateLabel.frame.maxX + 10
        hostLabel.frame = CGRect(x: x, y: y, width: s.hostW, height: s.methodsH)
        y = methodsLabel.frame.maxY
        //
        x = LRSpacing
        let shortTarget = s.session.req_target.components(separatedBy: " (").first
        if shortTarget != "" {
            targetLabel.frame = CGRect(x: x, y: y, width: s.targetW, height: s.targetH)
            x = targetLabel.frame.maxX + 10
        }
//        let fullSrcHost = s.session.srchost_str + ":" + s.session.srcport_str
        let fullDstHost = s.session.dsthost_str + ":" + s.session.dstport_str
        localAddress.frame = CGRect(x: x, y: y, width: s.localW, height: s.targetH)
        x = localAddress.frame.maxX + 10
        let re = fullDstHost
        if re != "" && re != ":" {
            remoteAddress.frame = CGRect(x: x, y: y, width: s.remoteW, height: s.targetH)
        }
        y = localAddress.frame.maxY
        //
        x = LRSpacing
        timeLabel.frame = CGRect(x: x, y: y, width: s.timeW, height: s.timeH)
        x = timeLabel.frame.maxX + 15
        upImage.frame = CGRect(x: x - 10, y: y, width: s.timeH/2, height: s.timeH)
        upLabel.frame = CGRect(x: x, y: y, width: s.upW, height: s.timeH)
        x = upLabel.frame.maxX + 12
        downImage.frame = CGRect(x: x - 10, y: y, width: s.timeH/2, height: s.timeH)
        downLabel.frame = CGRect(x: x, y: y, width: s.downW, height: s.timeH)


        if s.isImage {
            previewImage.frame = CGRect(x: SCREENWIDTH - LRSpacing - 50, y: s.sessionCellHeight - SessionItem.BottomSpacint - 50, width: 50, height: 50)
            moreBtn.frame = CGRect(x: SCREENWIDTH - LRSpacing - 50 - moreBtnW - 5, y: s.sessionCellHeight - moreBtnH, width: moreBtnW, height: moreBtnH)
        }else{
            moreBtn.frame = CGRect(x: SCREENWIDTH - LRSpacing - moreBtnW + 5, y: s.sessionCellHeight - moreBtnH, width: moreBtnW, height: moreBtnH)
        }

        stateLine.frame = CGRect(x: 0, y: 0, width: 3, height: s.sessionCellHeight)
        lineView.frame = CGRect(x: 0, y: s.sessionCellHeight, width: SCREENWIDTH, height: 1)
    }
    
    func resetData() -> Void {
        resetUI()
        uriLabel.text = session?.uri

        methodsLabel.text = session?.session?.method   // get\post...
        methodsLabel.textColor = .white
        methodsLabel.textAlignment = .center
        methodsLabel.backgroundColor = ColorM
        methodsLabel.clipsToBounds = true
        methodsLabel.layer.cornerRadius = (session?.methodsH ?? 1) / 4
        if let method = session?.session.method, method.lowercased() == "connect" {
            methodsLabel.backgroundColor = ColorSH
        }
        if let type = session?.type, type != "" {
            typeLabel.isHidden = false
            typeLabel.text = session?.type      // .gif\.js\.css
            typeLabel.textAlignment = .center
            typeLabel.backgroundColor = ColorR
            typeLabel.textColor = .white
            typeLabel.clipsToBounds = true
            typeLabel.layer.cornerRadius = (session?.methodsH ?? 1) / 4
        }else{
            typeLabel.isHidden = true
        }


        stateLabel.text = session?.state
        stateLabel.textColor = ColorSH
        stateLabel.layer.borderColor = ColorSH.cgColor
        stateLabel.layer.borderWidth = 1
        stateLabel.clipsToBounds = true
        stateLabel.layer.cornerRadius = (session?.methodsH ?? 1) / 4
        stateLabel.textAlignment = .center
        stateLine.backgroundColor = ColorSH
        if let state = session?.state.toInt(){
            /* 1xx:表示信息提示、2xx:表示成功、3xx:重定向、4xx:客户端出现错误、5xx服务器出现错误 */
            if state < 200 {
                stateLabel.textColor = ColorSH
                stateLabel.layer.borderColor = ColorSH.cgColor
                stateLine.backgroundColor = ColorSH
            }
            if state >= 200 , state < 300 {
                stateLabel.textColor = ColorSG
                stateLabel.layer.borderColor = ColorSG.cgColor
                stateLine.backgroundColor = ColorSG
            }
            if state >= 300, state < 400 {
                stateLabel.textColor = ColorSY
                stateLabel.layer.borderColor = ColorSY.cgColor
                stateLine.backgroundColor = ColorSY
            }
            if state >= 400 {
                stateLabel.textColor = ColorSR
                stateLabel.layer.borderColor = ColorSR.cgColor
                stateLine.backgroundColor = ColorSR
            }
        }else{
            typeLabel.isHidden = true
        }
        hostLabel.text = session?.session?.host     // xxx.xxx
        let shortTarget = session?.session?.req_target.components(separatedBy: " (").first
        targetLabel.text = shortTarget?.urlDecoded()    // Safari\qq
        
        var fullSrcHost = ""
        if let srcHost = session?.session?.srchost_str, srcHost != "",
           let srcPort = session?.session?.srcport_str, srcPort != ""
        {
            fullSrcHost = srcHost + ":" + srcPort
        }
//        let fullSrcHost = session?.session?.srchost_str + ":" + session?.session?.srcport_str
//        let fullDstHost = session?.session?.dsthost_str + ":" + session?.session?.dstport_str
        localAddress.text = fullSrcHost  // 127.0.0.1:8734 \ 192.168.1.43:8735
        
        var fullDstHost = ""
        if let dstHost = session?.session?.dsthost_str, dstHost != "",
           let dstPort = session?.session?.dstport_str, dstPort != ""
        {
            fullDstHost = dstHost + ":" + dstPort
        }
        remoteAddress.text = fullDstHost  // 87.234.12.6

        timeLabel.text = session?.time
        upLabel.text = session?.up
        downLabel.text = session?.down

        previewImage.image = nil
        if session?.isImage ?? false {
            previewImage.isHidden = false
            session?.session.parse(finished: { reqLinePath, reqHeadPath, reqBodyPath, rspLinePath, rspHeadPath, rspBodyPath in
                if let body = rspBodyPath {
//                    if let img = YYImage(contentsOfFile: body) {
//                        self.previewImage.image = img
//                        self.previewImage.stopAnimating()
//                    }
//                    self.previewImage.image = YYImage(contentsOfFile: body)
                    self.previewImage.yy_setImage(with: URL(fileURLWithPath: body), placeholder: nil)
                }
            })
//            let imgPath = ""//"\(MitmService.getStoreFolder())\(session?.session.fileFolder ?? "error")/\(session?.session.rspBody ?? "")"
            // 从缓存、异步获取
//            previewImage.yy_setImage(with: URL(fileURLWithPath: imgPath), placeholder: nil)
//            previewImage.stopAnimating()
            
        }else{
            previewImage.isHidden = true
        }
    }
    
    @objc func viewDidTouch(){
        delegate?.sessionCellSelectedChange(session: session?.session, selected: isSelected,indexPath: indexPath)
    }
    
    @objc func moreDidClick(){
        delegate?.moreBtnDidClick(session: session?.session)
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
//        guard let s = session else { return }
//
//        methodsLabel.backgroundColor = ColorM
//        if s.session.methods?.lowercased() == "connect" {
//            methodsLabel.backgroundColor = ColorSH
//        }
//        typeLabel.backgroundColor = ColorR
//        previewImage.stopAnimating()
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        if editing {
            if tap == nil {
                tap = UITapGestureRecognizer(target: self, action: #selector(viewDidTouch))
                addGestureRecognizer(tap!)
            }
        }else{
            if tap != nil {
                removeGestureRecognizer(tap!)
                tap = nil
            }
        }
        guard let s = session else { return }
        moreBtn.isHidden = editing
        stateLine.isHidden = editing
        let offX = SCREENWIDTH - LRSpacing - 50
        UIView.animate(withDuration: 0.3) {
            if s.isImage {
                self.previewImage.frame = CGRect(x: offX - (editing ? 30 : 0), y: self.previewImage.frame.origin.y, width: 50, height: 50)
            }
        }
    }
    
}

extension String {
    
    //将原始的url编码为合法的url
    func toUrlEncoded() -> String? {
        let encodeUrlString = self.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed)
        return encodeUrlString
    }
    
    //将编码后的url转换回原始的url
    func urlDecoded() -> String {
        return self.removingPercentEncoding ?? ""
    }
}
