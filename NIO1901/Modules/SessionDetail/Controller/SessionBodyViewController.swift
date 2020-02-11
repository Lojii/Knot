//
//  SessionBodyViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/20.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices
import Highlightr
import YYImage

class SessionBodyViewController: BaseViewController {

    var textView : UITextView!
    var currentFormatter: AFormatter!
    var imageView:YYAnimatedImageView!
    
    var highlightr : Highlightr!
    let textStorage = CodeAttributedString()
    var session:Session!
    var showRSP:Bool = true
    var type:String = ""
    var encoding:String = ""
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
        
        type = session.rspType.getRealType()
        encoding = session.rspEncoding
        if !showRSP {
            type = session.reqType.getRealType()
            encoding = session.reqEncoding
        }
        textStorage.language = "Tex"
        
//        if type == "json" {
//            textStorage.language = "json"
//        }
//        if type == "javascript" {
//            textStorage.language = "javascript"
//        }
        
        highlightr = textStorage.highlightr
        textStorage.highlightr.setTheme(to: "vs")
        
        let moreImg = UIImage(named: "more1")?.imageWithTintColor(color: ColorM)
        rightBtn.setImage(moreImg, for: .normal)
        rightBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: LRSpacing)
        rightBtn.imageView?.contentMode = .scaleAspectFit
        
        updateData()
    }
    
    func updateData()
    {
        let filePath = "\(session.fileFolder ?? "error")/\(showRSP ? session.rspBody : session.reqBody)"
        let nfilePath = "\(MitmService.getStoreFolder())\(filePath)"
        let tvFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        if FileManager.default.fileExists(atPath: nfilePath) {
            do{
                var data = try Data(contentsOf: URL(fileURLWithPath: "\(nfilePath)"))
                if CompressTypes.contains(encoding) {  // 解码数据，解压之类
                    if encoding != "gzip"{
                        print("非gzip编码格式:\(encoding)")
                    }
                }
                if data.isGzipped {
                    var unzipData1 = try data.gunzipped()
                    if unzipData1.count == 0 {
                        unzipData1 = data.gunzip() ?? data.unzip() ?? data.gunzip() ?? data.inflate() ?? Data()
                    }
                    if unzipData1.count > 0 {
                        data = unzipData1
                    }
//                    data = try data.gunzipped()
                }
                if ImageTypes.contains(type) {
                    let yyImg = YYImage(data: data)
                    outputItems = ["Export image".localized,"Export raw data".localized,"View raw data".localized]
                    outputHandler = { index in
                        if index == 0 {
                            if yyImg != nil {
                                VisualActivityViewController.share(image: yyImg!, on: self)
                            }else{
                                VisualActivityViewController.share(url: URL(fileURLWithPath: "\(nfilePath)"), on: self)
                            }
                        }
                        if index == 1 {
                            VisualActivityViewController.share(url: URL(fileURLWithPath: "\(nfilePath)"), on: self)
                        }
                        if index == 2 {
                            let vc = SessionDataViewController(session: self.session, showRSP: self.showRSP)
                            self.navigationController?.pushViewController(vc, animated: true)
                        }
                    }
                    // show image
                    //YYImage(contentsOfFile: nfilePath)
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
                }else{
                    
                    if let fileStr = String(data: data, encoding: .utf8) ,fileStr != "" {
                        navTitle = "\(type) (\(Int(fileStr.count)))"
                        navTitleColor = ColorA
                        // 文本展示
                        let layoutManager = NSLayoutManager()
                        textStorage.addLayoutManager(layoutManager)
                        let textContainer = NSTextContainer(size: CGSize(width: SCREENWIDTH, height: 999999999))
                        layoutManager.addTextContainer(textContainer)
                        
                        textView = UITextView(frame: tvFrame, textContainer: textContainer)
                        textView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
                        textView.autocorrectionType = UITextAutocorrectionType.no
                        textView.autocapitalizationType = UITextAutocapitalizationType.none
                        textView.isEditable = false
                        textView.textColor = ColorB
                        textView.font = Font13
                        textView.backgroundColor = .clear
                        view.addSubview(textView)
                        var showText = fileStr
                        // 甭管什么，先转换了再说
                        if let json = try? JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions()){
                            if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                                if let jsonString = String(data: jsonData, encoding: .utf8) {
                                    showText = jsonString
                                    textStorage.language = "json"
                                }
                            }
                        }
                        if type == "json" {
                            textStorage.language = "json"
                            do {
                                let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
                                let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
                                if let jsonString = String(data: jsonData, encoding: .utf8) {
                                    showText = jsonString
                                } else {
                                    print("Parsing Json null ")
                                }
                            } catch {
                                print("Parsing Json error: \(error)")
                            }
                        }else if JSTypes.contains(type) {
                            textStorage.language = "javascript"
                        }else  if type == "html" {
                            textStorage.language = "html"
                        }else if CSSTypes.contains(type) {
                            textStorage.language = "css"
                        }else if urlEncodedTypes.contains(type) {
                            showText = fileStr.urlDecoded()
                        }
                        if type == "" {
                            navTitle = "Text (\(Int(fileStr.count)))"
                        }
                        textView.text = showText
                        outputItems = ["Export text".localized,"Export raw data".localized,"View raw data".localized]
                        outputHandler = { index in
                            if index == 0 {
                                VisualActivityViewController.share(text: showText, on: self, self.textStorage.language == "Tex" ? nil : self.textStorage.language)
                            }
                            if index == 1 {
                                VisualActivityViewController.share(text: fileStr, on: self)
                            }
                            if index == 2 {
                                let vc = SessionDataViewController(session: self.session, showRSP: self.showRSP)
                                self.navigationController?.pushViewController(vc, animated: true)
                            }
                        }
                    }else{
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
                        
                        let originalData = try Data(contentsOf: URL(fileURLWithPath: "\(nfilePath)"))
                        navTitle = "Hex (\(Float(originalData.count).bytesFormatting())))"
                        navTitleColor = ColorA
                        
                        currentFormatter.data = originalData
                        textView.text = currentFormatter.formattedString
                        title = "Hex \(originalData.count)"
                        outputItems = ["Export raw data".localized]
                        outputHandler = { index in
                            if index == 0 {
                                VisualActivityViewController.share(url: URL(fileURLWithPath: "\(nfilePath)"), on: self)
                            }
                        }
                    }
                }
            }catch{
                print("读取失败:\(error)")
                navTitle = "Read failure".localized
                navTitleColor = ColorA
            }
        }

    }
    
    override func rightBtnClick() {
        
        PopViewController.show(titles: outputItems, viewController: self, itemClickHandler: outputHandler)
    }
    
}
