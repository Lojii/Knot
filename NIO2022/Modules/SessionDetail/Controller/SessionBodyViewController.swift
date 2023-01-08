//
//  SessionBodyViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/20.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import Highlightr
import YYImage
import NIOMan
import BrotliKit
import WebKit
//import GSPlayer

enum EncodingType{
    case gzip
    case deflate
    case br
    case compress
}

class SessionBodyViewController: BaseViewController {

    var textView : UITextView!  // 文本
    var currentFormatter: AFormatter! // 十六进制
    var imageView:YYAnimatedImageView! // 图片
//    var videoPlayer: VideoPlayerView!
//    var audioPlayer:Player!// 音频播放器
    // pdf文档查看器
    // body信息卡片
    
    var session:Session!
    var showRSP:Bool = true
    
    var filePath:String = "" //
    var fileSize:UInt64 = 0  //

    var type:String = "" //content_type：image/jpeg video/mpeg4 audio/mp3 text/plain
    var suffix:String = "" //suffix ： json，js, jpeg, mp4 ...
    var encoding:String = "" // gzip,compress,deflate,br
    // 更多操作
    var outputItems = [String]()
    var outputHandler: ((Int) -> Void)?
    
    init(session:Session,showRSP:Bool) {
        self.session = session
        self.showRSP = showRSP
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // charset  utf-8
        type = showRSP ? session.rsp_content_type : session.req_content_type
        suffix = showRSP ? session.suffix : ""
        encoding = showRSP ? session.rsp_encode : session.req_encode

        let moreImg = UIImage(named: "more1")?.imageWithTintColor(color: ColorM)
        rightBtn.setImage(moreImg, for: .normal)
        rightBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: LRSpacing)
        rightBtn.imageView?.contentMode = .scaleAspectFit

        session.parse { reqLinePath, reqHeadPath, reqBodyPath, rspLinePath, rspHeadPath, rspBodyPath in
            self.updateData(bodyPath: (self.showRSP ? rspBodyPath : reqBodyPath))
        }
        
    }
    
    func updateData(bodyPath:String?)
    {
        if bodyPath == nil { return }
        filePath = bodyPath!
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: filePath)
            let dict = attr as NSDictionary
            fileSize = dict.fileSize()
        } catch {
            print("Error: \(error)")
        }
        // 1、预处理，大文件通常不会有encoding
        // 2、判断文件类型：音频、视频、文本、图片、pdf类型的文件，执行对应的展示
        // 3、尝试读取成文本
        // 4、根据文件大小，决定展示信息还是十六进制
        // 5、失败
        let zipType = encoding.lowercased()
        if zipType.contains("gzip") {
            zipHandle(.gzip)
        }else if zipType.contains("deflate"){
            zipHandle(.deflate)
        }else if zipType.contains("br"){
            zipHandle(.br)
        }else if zipType.contains("compress"){
            zipHandle(.compress)
        }else{
            if fileSize < 1024000 { // 对小于1M的未知编码数据，默认尝试一轮解压处理
                zipHandle(.gzip)
            }else{
                dataHandle(nil)
            }
//            dataHandle(nil) // 不需要预处理
        }
    }
    
    func zipHandle(_ zipType:EncodingType){
        guard var data = try? Data(contentsOf: URL(fileURLWithPath: "\(filePath)")) else {
            // showEmpty\Error ?
            return
        }
//        switch zipType {
//        case .gzip:
//            if let unZipData = data.gunzip() { data = unZipData }
//            break
//        case .deflate:
//            if let unZipData = data.inflate() { data = unZipData }
//            break
//        case .br: // Brotli
//            if let unZipData = NSData(data: data).decompressBrotli() { data = unZipData }
//            break
//        case .compress:
//            if let unZipData = data.unzip() ?? data.decompress(withAlgorithm: .zlib) ?? data.decompress(withAlgorithm: .lz4) ?? data.decompress(withAlgorithm: .lzfse) ?? data.decompress(withAlgorithm: .lzma) { data = unZipData }
//            break
//        }
        // 这乱七八糟的返回数据，不按常理出牌啊！怎么能逼我写这么🤢的代码！！！
        if let unZipData = data.gunzip() {
            print("gunzip()")
            data = unZipData
        }else if let unZipData = data.unzip() {
            print("unzip()")
            data = unZipData
        }else if let unZipData = data.inflate() {
            print("inflate()")
            data = unZipData
        }else if let unZipData = NSData(data: data).decompressBrotli() {
            print("decompressBrotli()")
            data = unZipData
        }else if let unZipData = data.decompress(withAlgorithm: .zlib) {
            print("zlib()")
            data = unZipData
        }else if let unZipData = data.decompress(withAlgorithm: .lz4) {
            print("lz4()")
            data = unZipData
        }else if let unZipData = data.decompress(withAlgorithm: .lzfse) {
            print("lzfse()")
            data = unZipData
        }else if let unZipData = data.decompress(withAlgorithm: .lzma) {
            print("lzma()")
            data = unZipData
        }else{
            print("nozip()")
        }
        dataHandle(data)
    }
    
    func dataHandle(_ data: Data?){
        if type.lowercased().contains("image") {  // 图片
            showImage(data)
//        }else if type.lowercased().contains("video"){  // 视频
//            showVideo(data)
//        }else if type.lowercased().contains("audio"){  // 音频
//            showAudio(data)
        }else if type.lowercased().contains("text") || type.lowercased().contains("json") || type.lowercased().contains("javascript"){
            showText(data)
//        }else if type.lowercased().contains("pdf"){ // 文档
//            showPdf(data)
        }else{
            if !tryShowText(data) {
                // 如果文件超过10兆且未知，则不读取
                if fileSize > 10240000 {
                    showInfo(data)
                }else{
                    showHex(data)
                }
            }
        }
    }
    
    func showImage(_ data: Data?){ //
        var yyImg:YYImage?
        if data != nil {
            yyImg = YYImage(data: data!)
        }else{
            yyImg = YYImage(contentsOfFile: filePath)
        }
        outputItems = ["Export image".localized,"Export raw data".localized,"View raw data".localized]
        outputHandler = { index in
            if index == 0 {
                KnotPurchase.check(.HappyKnot) { res in
                    if(res){
                        if yyImg != nil {
                            VisualActivityViewController.share(image: yyImg!, on: self)
                        }else{
                            VisualActivityViewController.share(url: URL(fileURLWithPath: "\(self.filePath)"), on: self)
                        }
                    }
                }
            }
            if index == 1 {
                KnotPurchase.check(.HappyKnot) { res in
                    if(res){
                        VisualActivityViewController.share(url: URL(fileURLWithPath: "\(self.filePath)"), on: self)
                    }
                }
            }
            if index == 2 {
                let vc = SessionDataViewController(session: self.session, showRSP: self.showRSP)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        }
        // show image
        imageView = YYAnimatedImageView(image: yyImg)
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        let w = SCREENWIDTH - LRSpacing * 2
        var h = w * SCREENHEIGHT / SCREENWIDTH
        let maxH = SCREENHEIGHT - NAVGATIONBARHEIGHT * 2
        h = h > maxH ? maxH : h
        imageView.snp.makeConstraints { (m) in
            m.centerX.centerY.equalToSuperview()
            m.width.equalTo(w)
            m.height.equalTo(h)
        }
        imageView.setupForImageViewer(.black)
        navTitle = "\(type) (\(Int(yyImg?.size.width ?? 0))×\(Int(yyImg?.size.height ?? 0)))"
        navTitleColor = ColorA
    }
    
    func showText(_ data: Data?){ //
        let tvFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let str:String?
        if data != nil {
            str = String(data: data!, encoding: .utf8)
        }else{
            str = try? String(contentsOfFile: filePath, encoding: .utf8)
        }
        if let fileStr = str ,fileStr != "" {
            navTitle = "\(type) (\(Int(fileStr.count)))"
            navTitleColor = ColorA
            // 文本展示
            textView = UITextView(frame: tvFrame)
            textView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            textView.autocorrectionType = UITextAutocorrectionType.no
            textView.autocapitalizationType = UITextAutocapitalizationType.none
            textView.isEditable = false
            textView.textColor = .white
            textView.font = Font13
            textView.backgroundColor = ColorA
            view.addSubview(textView)
            // 尝试格式化json
            var showText = fileStr
            let toJsonData = data ??  fileStr.data(using: .utf8) ?? Data()
            if let json = try? JSONSerialization.jsonObject(with: toJsonData, options: JSONSerialization.ReadingOptions()){
                if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        showText = jsonString
                    }
                }
            }
            textView.text = showText
            if showText.count < 300000 { // 控制转换时间在30秒内
                DispatchQueue.global().async {
                    let highlightr = Highlightr()
                    highlightr?.setTheme(to: "agate")
//                    let start = CFAbsoluteTimeGetCurrent()
                    let highlightedCode = highlightr?.highlight(showText, as: nil)
//                    print("转换完成：\(showText.count)----" + String(CFAbsoluteTimeGetCurrent() - start) + "seconds")
                    DispatchQueue.main.async {
                        self.textView.attributedText = highlightedCode
                    }
                }
            }
            
            outputItems = ["Export text".localized,"Export raw data".localized,"View raw data".localized]
            outputHandler = { index in
                if index == 0 {
                    KnotPurchase.check(.HappyKnot) { res in
                        if(res){
                            VisualActivityViewController.share(text: showText, on: self, nil)
                        }
                    }
                }
                if index == 1 {
                    KnotPurchase.check(.HappyKnot) { res in
                        if(res){
                            VisualActivityViewController.share(text: fileStr, on: self)
                        }
                    }
                }
                if index == 2 {
                    let vc = SessionDataViewController(session: self.session, showRSP: self.showRSP)
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            }
        }else{
            showHex(data)
        }
    }
    
    func showVideo(_ data: Data?){ //
        print("视频")
        showHex(data)
    }
    func showAudio(_ data: Data?){ //
        print("音频")
        showHex(data)
    }
    
    func showPdf(_ data: Data?){ //
        print("PDF")
        showHex(data)
    }
    
    func showHex(_ data: Data?){ // 十六进制展示
        print("Hex")
        let tvFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        // 非文本内容，展示原始十六进制数据
        textView = UITextView(frame: tvFrame)
        textView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        textView.autocorrectionType = UITextAutocorrectionType.no
        textView.autocapitalizationType = UITextAutocapitalizationType.none
        textView.isEditable = false
        textView.textColor = ColorA
        textView.font = FontC10
        textView.backgroundColor = .clear
        view.addSubview(textView)
        
        currentFormatter = AFormatter()
        currentFormatter.numberOfCharactersPerLine = 16 + (16 * 3) + (12) + 1
        currentFormatter.currentDisplaySize = FORMATTER_DISPLAY_SIZE_WORD
        
        var originalData = data
        if originalData == nil {
            originalData = (try? Data(contentsOf: URL(fileURLWithPath: filePath))) ?? Data()
        }
        navTitle = "Hex (\(Float(originalData!.count).bytesFormatting())))"
        navTitleColor = ColorA

        currentFormatter.data = originalData
        textView.text = currentFormatter.formattedString
        title = "Hex \(originalData!.count)"
        outputItems = ["Export raw data".localized]
        outputHandler = { index in
            KnotPurchase.check(.HappyKnot) { res in
                if(res){
                    if index == 0 {
                        VisualActivityViewController.share(url: URL(fileURLWithPath: self.filePath), on: self)
                    }
                }
            }
        }
    }
    
    func showInfo(_ data: Data?){ // 文件太大，则展示文件类型等信息
        print("Info")
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = ColorB
        label.text = "Unable to open".localized
        label.font = Font24
        view.addSubview(label)
        label.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        outputItems = ["Export raw data".localized]
        outputHandler = { index in
            KnotPurchase.check(.HappyKnot) { res in
                if(res){
                    if index == 0 {
                        VisualActivityViewController.share(url: URL(fileURLWithPath: self.filePath), on: self)
                    }
                }
            }
        }
    }
    
    func tryShowText(_ data: Data?) -> Bool { // 尝试其中文本
//        print("try text")
        var str:String? = nil
        if data != nil {
            str = String(data: data!, encoding: .utf8)
        }else{
            str = try? String(contentsOfFile: filePath, encoding: .utf8)
        }
        if str != nil {
            showText(data)
            return true
        }
        return false
    }
    
    override func rightBtnClick() {
        
        PopViewController.show(titles: outputItems, viewController: self, itemClickHandler: outputHandler)
    }
    
    deinit {
        print("SessionBodyViewController deinit !")
    }
    
}
