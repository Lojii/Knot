//
//  SessionTimeView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/18.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class SessionTimeView: UIView {

    var times:[[String:String]]
    
    var titleLabel:UILabel
    var contentView:UIView
    //    var contentLabel:UILabel
    var titleHeight:CGFloat = 30
    var contentHeight:CGFloat = 0
    var itemHeight:CGFloat = 0
    var subItemHeight:CGFloat = 30
    
    init(title:String,times:[[String:String]]) {
        
        self.times = times
        
        let attrStr = title.addAttributes(.font(Font16), .color(ColorA))
        
        titleLabel = UILabel()
        titleLabel.numberOfLines = 1
        titleLabel.attributedText = attrStr
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.isUserInteractionEnabled = true
        
        super.init(frame: CGRect.zero)
        addSubview(titleLabel)
        addSubview(contentView)
        addSubviews()
        setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addSubviews(){
        var offY:CGFloat = 0
        if times.count < 2 {
            let itemView = TimeLineView(key: "unfinished".localized, value: "", start: 0, lenght: 0, isLast: true)
            itemView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: subItemHeight)
            offY = offY + subItemHeight
            contentView.addSubview(itemView)
            contentHeight = offY
            return
        }
        guard let startTime = Double(times[0].values.first ?? "") else{ print("error:开始时间未知"); return }
        guard let endTime = Double(times.last?.values.first ?? "") else{ print("error:结束时间未知"); return }
        let sumTime = endTime - startTime
        guard sumTime > 0.0 else { print("error:总时间小于0？"); return }
        let sumLenght = Double(SCREENWIDTH)
        
        var offX:Double = 0
        for i in 1..<times.count {
            let s = times[i-1]
            let e = times[i]
            if let start = Double(s.values.first ?? ""), let end = Double(e.values.first ?? "") {
                var sum = end - start
                let lenght =  sum / sumTime * sumLenght
                var unit = "s"
                if sum < 1 {
                    unit = "ms"
                    sum = sum * 1000
                }
                let sumStr = NSString(format: "%.5f", sum)
                let numbs = sumStr.components(separatedBy: ".")
                let shiwei = numbs.first!
                var xiaoshuwei = ""
                if numbs.count == 2 {
                    xiaoshuwei = numbs.last!
                    xiaoshuwei = xiaoshuwei.prefix(2).lowercased()
                }
                xiaoshuwei = xiaoshuwei.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
                xiaoshuwei = xiaoshuwei == "" ? "" : ".\(xiaoshuwei)"
                let itemView = TimeLineView(key: e.keys.first!, value: "\(shiwei)\(xiaoshuwei) \(unit)", start: CGFloat(offX), lenght: CGFloat(lenght), isLast: i == times.count-1)
                offX = offX + lenght
                itemView.frame = CGRect(x: 0, y: offY, width: SCREENWIDTH, height: subItemHeight)
                offY = offY + subItemHeight
                contentView.addSubview(itemView)
            }
        }
        contentHeight = offY
    }
    
    func setUI(){
        
        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(titleHeight)
            m.right.equalToSuperview()
        }
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.right.equalToSuperview()
            m.height.equalTo(contentHeight)
        }
        itemHeight = contentHeight + titleHeight + LRSpacing
    }
}

class TimeLineView:UIView{
    var key:String
    var value:String
    var color:UIColor
    var start:CGFloat
    var lenght:CGFloat
    var isLast = false
    
    var keyLabel:UILabel
    var valueLabel:UILabel
    var lineView:UIView
    
    var colorView:UIView
    
//    var height:CGFloat = 0
    
    init(key:String,value:String,start:CGFloat,lenght:CGFloat,color:UIColor = ColorSG,isLast:Bool = false) {
        self.key = key
        self.value = value
        self.lenght = lenght
        self.start = start
        self.color = color
        self.isLast = isLast
        keyLabel = UILabel.initWith(color: ColorA, font: Font14, text: key, frame: CGRect.zero)
        keyLabel.numberOfLines = 0
        valueLabel = UILabel.initWith(color: ColorA, font: Font14, text: value, frame: CGRect.zero)
        valueLabel.numberOfLines = 0

        lineView = UIView()
        lineView.backgroundColor = ColorF
        lineView.isHidden = isLast
        
        colorView = UIView()
        colorView.backgroundColor = color
        colorView.alpha = 0.8
        super.init(frame: CGRect.zero)
        setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI(){
        addSubview(colorView)
        addSubview(keyLabel)
        addSubview(valueLabel)
        addSubview(lineView)
        
        colorView.snp.makeConstraints { (m) in
            m.height.centerY.equalToSuperview()
            m.left.equalToSuperview().offset(start)
            m.width.equalTo(lenght)
        }
        
        valueLabel.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.right.equalToSuperview().offset(-LRSpacing)
            m.height.equalToSuperview()
        }
        keyLabel.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.left.equalToSuperview().offset(LRSpacing)
            m.height.equalToSuperview()
            m.right.equalTo(valueLabel.snp.left)
        }
        lineView.snp.makeConstraints { (m) in
            m.bottom.equalToSuperview()
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing)
            m.height.equalTo(1)
        }
    }
}
