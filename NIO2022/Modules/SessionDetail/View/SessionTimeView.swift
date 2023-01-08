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
    var titleHeight:CGFloat = 30
    
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

    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addSubviews(){
        let stackView = UIStackView()
        stackView.axis = .vertical
        contentView.addSubview(stackView)
        
        var lastV:UIView?
        
        if times.count < 2 {
            let itemView = TimeLineView(key: "unfinished".localized, value: "", start: 0, lenght: 0, isLast: true)
            stackView.addArrangedSubview(itemView)
            lastV = itemView
        }else{
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
                    stackView.addArrangedSubview(itemView)
                    lastV = itemView
                }
            }
        }
        
        titleLabel.snp.makeConstraints { (m) in
            m.top.left.equalToSuperview().offset(LRSpacing)
            m.height.equalTo(titleHeight)
            m.right.equalToSuperview()
        }
        stackView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalToSuperview()
            make.right.equalToSuperview()
            if lastV != nil {
                make.bottom.equalTo(lastV!.snp_bottom)
            }
        }
        
        contentView.snp.makeConstraints { (m) in
            m.top.equalTo(titleLabel.snp.bottom)
            m.left.right.equalToSuperview()
            m.bottom.equalTo(stackView.snp_bottom)
        }
        
        snp.makeConstraints { make in
            make.bottom.equalTo(contentView.snp_bottom)
        }
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
        addSubview(lineView)
        addSubview(colorView)
        addSubview(keyLabel)
        addSubview(valueLabel)
        
        colorView.snp.makeConstraints { (m) in
            m.height.centerY.equalToSuperview()
            m.left.equalToSuperview().offset(start)
            m.width.equalTo(lenght)
        }
        
        keyLabel.snp.makeConstraints { (m) in
            m.top.equalTo(snp_top).offset(5)
            m.left.equalToSuperview().offset(LRSpacing)
        }
        
        valueLabel.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.right.equalToSuperview().offset(-LRSpacing)
        }
        
        lineView.snp.makeConstraints { (m) in
            m.bottom.equalToSuperview()
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing)
            m.height.equalTo(1)
        }
        
        snp.makeConstraints { make in
            make.bottom.equalTo(keyLabel.snp_bottom).offset(5)
        }
    }
}
