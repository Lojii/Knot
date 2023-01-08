//
//  BodyPreView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/16.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import YYImage
import NIOMan

protocol BodyPreViewDelegate: class {
    func bodyPreView(preView:BodyPreView?,showImage:UIImage)
    func bodyPreView(preView:BodyPreView?,unZip:String)
    func bodyPreView(preView:BodyPreView?,showPDF:String)
    func bodyPreView(preView:BodyPreView?,showDOC:String)
    func bodyPreView(preView:BodyPreView?,showJSON:String)
    func bodyPreView(preView:BodyPreView?,showTXT:String)
    func bodyPreView(preView:BodyPreView?,showXML:String)
    func bodyPreView(preView:BodyPreView?,showJS:String)
    func bodyPreView(preView:BodyPreView?,showCSS:String)
}

class BodyPreView: UIView {
    
    weak var delegate:BodyPreViewDelegate?
    var titleView:UIView?
    var contentView:UIView?
    var operationView:UIView?
    
    var infos = [[String:String]]()
    
    
    static func getPreView(_ type:String, filePath:String) -> BodyPreView {
        let preView = BodyPreView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
//        let nfilePath = "\(MitmService.getStoreFolder())\(filePath)"
        let fn = FileManager.default
        if !fn.fileExists(atPath: filePath) {
            preView.infos.append(["Tips" : "File does not exist".localized])
            return preView
        }
        // 获取文件大小
        let fileSize = getSize(url: URL(fileURLWithPath: filePath))
        preView.infos.append(["Data size".localized : "\(Float(fileSize).bytesFormatting())"])

        let ts = type.components(separatedBy: ";")
        let contentType = ts.first ?? "unknow"
        preView.infos.append(["Data type".localized : "\(contentType.lowercased())"])
        if ts.count > 1 {
            let otherInfo = ts[1]
            preView.infos.append(["Extra" : "\(otherInfo)"])
        }
        let t = (type.components(separatedBy: ";").first ?? "").lowercased().getRealType()
        // png\jpeg\gif\webP
        if ImageTypes.contains(t) {
            if let img = YYImage(contentsOfFile: filePath) {
                preView.infos.append(["Size".localized : "\(Int(img.size.width))×\(Int(img.size.height))"])
                preView.contentView = YYAnimatedImageView(image: img)
//                let frameCount = img.animatedImageFrameCount()
//                if frameCount > 1 {
//                    preView.infos.append(["帧" : "\(frameCount)"])
//                }
                preView.contentView?.contentMode = .scaleAspectFit
            }
        }
        // 视频长度、压缩率、证书文件...
        if preView.contentView == nil {
            preView.backgroundColor = ColorF
            let ccv = UIView()
            let typeLabel = UILabel()
            var tt = t.uppercased()
            if tt == "" { tt = "HEX" }
            typeLabel.text = tt
            typeLabel.font = Font24
            typeLabel.textColor = ColorC
            typeLabel.numberOfLines = 0
            typeLabel.textAlignment = .center
            ccv.addSubview(typeLabel)
            typeLabel.snp.makeConstraints { (m) in
                m.width.height.centerX.centerY.equalToSuperview()
            }
            preView.contentView = ccv
        }
        preView.addSubview(preView.contentView ?? UIView())
        preView.layoutSubV()
        return preView
    }
    
    func layoutSubV() -> Void {
        if let cv = contentView {
            cv.snp.makeConstraints { (m) in
                m.top.left.width.height.equalToSuperview()
            }
        }
    }
    
    static func getSize(url: URL)->UInt64{
        var fileSize : UInt64 = 0
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: url.path)
//            fileSize = attr[FileAttributeKey.size] as! UInt64
            let dict = attr as NSDictionary
            fileSize = dict.fileSize()
        } catch {
            print("Error: \(error)")
        }
        return fileSize
    }

}
