//
//  HomeHistoryCard.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/16.
//

import UIKit
import SnapKit
import NIOMan

class HomeHistoryCard: HomeCard {

    var didClick: (() -> Void)?
    
    var titleLabel:UILabel! // 历史任务
    var outLabel:UILabel!   // 上传
    var inLabel:UILabel!    // 下载
    var numLabel:UILabel!   // 会话数
    var sizeLabel:UILabel!  // 占用空间
    
    override init(frame: CGRect){
        super.init(frame: frame)
        setUI()
        refreshData()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshData), name: HistoryTaskDidChanged, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func cardDidClick() -> Void {
        didClick?()
    }
    
    func setUI() -> Void {
        
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardDidClick)))
        
        titleLabel = UILabel()
        titleLabel.font = Font18
        titleLabel.textColor = ColorB
        titleLabel.numberOfLines = 0
        titleLabel.text = "Historical task".localized
        addSubview(titleLabel)
        
        
        outLabel = UILabel()
        outLabel.font = Font16
        outLabel.textColor = ColorB
        outLabel.numberOfLines = 0
        outLabel.text = "\("Up".localized):0 M"
        addSubview(outLabel)
        
        inLabel = UILabel()
        inLabel.font = Font16
        inLabel.textColor = ColorB
        inLabel.numberOfLines = 0
        inLabel.text = "\("Down".localized):0 M"
        addSubview(inLabel)
        
        numLabel = UILabel()
        numLabel.font = Font16
        numLabel.textColor = ColorB
        numLabel.numberOfLines = 0
        numLabel.text = "\("Count".localized):0"
        addSubview(numLabel)
        
        sizeLabel = UILabel()
        sizeLabel.font = Font16
        sizeLabel.textColor = ColorB
        sizeLabel.numberOfLines = 0
        sizeLabel.text = "\("Disk space".localized):0 M"
        addSubview(sizeLabel)
        
        titleLabel.snp.makeConstraints { (m) in
            m.left.equalTo(snp.left).offset(HomeCard.LRMargin)
            m.right.equalTo(snp.right).offset(-HomeCard.LRMargin)
            m.top.equalTo(snp.top).offset(HomeCard.TBMargin)
        }
        
        outLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(13)
            make.left.equalTo(titleLabel.snp.left)
        }
        inLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(13)
            make.left.equalTo(outLabel.snp.right).offset(30)
        }
        
        numLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel.snp.left)
            make.top.equalTo(outLabel.snp.bottom).offset(5)
        }
        sizeLabel.snp.makeConstraints { make in
            make.top.equalTo(outLabel.snp.bottom).offset(5)
            make.left.equalTo(numLabel.snp.right).offset(30)
        }

        snp.makeConstraints { make in
            make.width.equalTo(HomeCard.CardWidth)
            make.bottom.equalTo(sizeLabel.snp_bottom).offset(HomeCard.TBMargin)
        }
    }

    @objc func refreshData(){
        NEManager.shared.loadCurrentStatus {[weak self] status in
            self?.calculateData(excludeCurrent: status == .on)
        }
    }
    
    func calculateData(excludeCurrent:Bool){
        var currentTaskId:String?
        if excludeCurrent {
            let gud = UserDefaults(suiteName: GROUPNAME)
            if let taskId = gud?.value(forKey: CURRENTTASKID) as? String {
                currentTaskId = taskId
            }
        }
        DispatchQueue.global().async {
            // 统计session表里的条数、流量总数、文件夹里所有文件的总和
            let size = self.fileSize(excludeTaskId: currentTaskId)
            let res = Session.calculate(excludeTaskId: currentTaskId)
            DispatchQueue.main.async {
                self.sizeLabel.text = "\("Disk space".localized):\(size.bytesFormatting())"
                self.inLabel.text = "\("Down".localized):\(res.i.bytesFormatting())" //
                self.outLabel.text = "\("Up".localized):\(res.o.bytesFormatting())"
                self.numLabel.text = "\("Count".localized):\(res.c)"
            }
        }
    }
    
    func singleFileSize(path:String) -> Double {
        let manager = FileManager.default
        var fileSize:Double = 0
        do {
            let attr = try manager.attributesOfItem(atPath: path)
            fileSize = Double(attr[FileAttributeKey.size] as! UInt64)
            let dict = attr as NSDictionary
            fileSize = Double(dict.fileSize())
        } catch {
            
        }
        return fileSize
    }
    
    func fileSize(excludeTaskId:String?) -> Float{
        if let folderPath = NIOMan.LogsPath()?.absoluteString.components(separatedBy: "file://").last {
            let manage = FileManager.default
            if !manage.fileExists(atPath: folderPath) {
                return 0
            }
            let childFilePath = manage.subpaths(atPath: folderPath)
            var fileSize:Double = 0
            for path in childFilePath! {
                let fileAbsoluePath = folderPath + path
                if excludeTaskId != nil {
                    if fileAbsoluePath.contains(excludeTaskId!) {
                        continue
                    }
                }
                fileSize += singleFileSize(path: fileAbsoluePath)
            }
            return Float(fileSize)
        }
        return 0
    }
    
}
