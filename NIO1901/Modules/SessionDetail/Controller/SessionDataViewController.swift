//
//  SessionDataViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/21.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

class SessionDataViewController: BaseViewController {

    var textView : UITextView!
    var currentFormatter: AFormatter!
    
    var session:Session!
    var showRSP:Bool = true
    var type:String = ""
    var encoding:String = ""
    
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
        
        let tvFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        textView = UITextView(frame: tvFrame)
        textView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        textView.autocorrectionType = UITextAutocorrectionType.no
        textView.autocapitalizationType = UITextAutocapitalizationType.none
        textView.isEditable = false
        textView.textColor = ColorA
        textView.font = FontC10
        view.addSubview(textView)
        
        currentFormatter = AFormatter()
        currentFormatter.numberOfCharactersPerLine = 16 + (16 * 3) + (12) + 1
        currentFormatter.currentDisplaySize = FORMATTER_DISPLAY_SIZE_WORD // //
        // FORMATTER_DISPLAY_SIZE_DWORD
        
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
        if FileManager.default.fileExists(atPath: nfilePath) {
            do{
                let data = try Data(contentsOf: URL(fileURLWithPath: "\(nfilePath)"))
                currentFormatter.data = data
                textView.text = currentFormatter.formattedString
            }catch{
                print("读取失败:\(error)")
            }
        }
        
    }
    
    override func rightBtnClick() {
        let filePath = "\(session.fileFolder ?? "error")/\(showRSP ? session.rspBody : session.reqBody)"
        let nfilePath = "\(MitmService.getStoreFolder())\(filePath)"
        PopViewController.show(titles: ["Export".localized], viewController: self ) { index in
            VisualActivityViewController.share(url: URL(fileURLWithPath: "\(nfilePath)"), on: self)
        }
    }

}
