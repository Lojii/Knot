//
//  SearchFocusView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/26.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

protocol SearchFocusViewDelegate: AnyObject {
    func focusViewDidFocuse(focuseOption:SearchOption)    // Focus
    func focusViewAddToFiter(focuseOption:SearchOption)   // 添加到过滤器
    func focusViewDidHiden() // 隐藏时候调用
}

class SearchFocusView: UIView {

    var _focusOption = SearchOption()
    var focusOption: SearchOption {
        get { return _focusOption }
        set {
            _focusOption = newValue
            setUI()
        }
    }
    var focusChange = false
    weak var delegate:SearchFocusViewDelegate?
    
    lazy var bgView: UIView = {
        let bgView = UIView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 300))
        bgView.backgroundColor = .black
        bgView.layer.opacity = 0.5
        bgView.isUserInteractionEnabled = true
        bgView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hiden)))
        return bgView
    }()
    lazy var contentView: UIScrollView = {
        let contentView = UIScrollView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 300))
        contentView.backgroundColor = .white
        contentView.clipsToBounds = true
        return contentView
    }()
    var doneBtn = UIButton()
    var resetBtn = UIButton()
    var addToFiterBtn = UIButton()
    
    lazy var operationView: UIView = {
        let operationView = UIView()
        operationView.backgroundColor = ColorF
        return operationView
    }()
    
    var contentHeight:CGFloat = 0
    var operationHeight:CGFloat = 40
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(bgView)
        bgView.frame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        addSubview(contentView)
        self.setUI()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUI(){
        let subVs = contentView.subviews
        for ov in operationView.subviews{
            ov.removeFromSuperview()
        }
        operationView.removeFromSuperview()
        for v in subVs { v.removeFromSuperview() }
        
        if focusOption.searchMap.count <= 0 {
            // 显示空白页和提示
            let tipLabel = UILabel()
            tipLabel.text = "No Focus !"
            tipLabel.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 40)
            tipLabel.textAlignment = .center
            tipLabel.font = Font13
            tipLabel.textColor = ColorB
            contentView.addSubview(tipLabel)
            contentView.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: tipLabel.frame.height)
            contentHeight = contentView.frame.height
            operationView.frame = CGRect(x: 0, y: contentView.frame.maxY, width: SCREENWIDTH, height: operationHeight)
            addSubview(operationView)
            operationView.isHidden = true
            return
        }
        var offY:CGFloat = 5
        var offX = LRSpacing
        let width = SCREENWIDTH - LRSpacing - 5
        let btnH:CGFloat = 25
        let btnSpacingH:CGFloat = 8 // 水平间隔
        let btnSpacingV:CGFloat = 8 // 垂直间隔
        let btnFont = Font13
        let titleH:CGFloat = 30
        
        for sm in focusOption.searchMap {
            guard let searchKey = sm.keys.first,let searchValues = sm.values.first else{
                print("NO SEARCH KEY OR NO SEARCHV ALUE !")
                return
            }
            if searchValues.count <= 0 {
                continue
            }
            // title
            let titleLabel = UILabel(frame: CGRect(x: offX, y: offY, width: SCREENWIDTH - LRSpacing * 2, height: titleH))
            titleLabel.text = "\(searchKey)"
            titleLabel.textColor = ColorB
            titleLabel.font = Font14
            titleLabel.textAlignment = .left
            contentView.addSubview(titleLabel)
            offY = offY + titleH
            for v in searchValues {
                var btnW = v.textWidth(font: btnFont) + 16
                if btnW > width { btnW = width }
                if btnW + offX > width {
                    offY = offY + btnH + btnSpacingV
                    offX = LRSpacing
                }
                let btn = UIButton()
                btn.setTitle(v, for: .normal)
                btn.titleLabel?.font = btnFont
                btn.setTitleColor(ColorB, for: .normal)
                btn.setTitleColor(.white, for: .selected)
                btn.setTitle("\(searchKey)", for: .disabled)
                btn.setBackgroundImage(UIImage.renderImageWithColor(ColorSG, size: CGSize(width: 1, height: 1)), for: .selected)
                btn.setBackgroundImage(UIImage.renderImageWithColor(ColorF, size: CGSize(width: 1, height: 1)), for: .normal)
                btn.frame = CGRect(x: offX, y: offY, width: btnW, height: btnH)
                btn.isSelected = true
                btn.addTarget(self, action: #selector(focuseBtnDidClick(btn:)), for: .touchUpInside)
                contentView.addSubview(btn)
                offX = offX + btnW + btnSpacingH
            }
            offY = offY + btnH + btnSpacingV
            offX = LRSpacing
        }
        let maxHeight = SCREENHEIGHT - NAVGATIONBARHEIGHT - 150
        contentHeight = offY > maxHeight ? maxHeight : offY
        contentView.contentSize = CGSize(width: 0, height: offY)
        contentView.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: contentHeight)
        operationView.frame = CGRect(x: 0, y: contentView.frame.maxY, width: SCREENWIDTH, height: operationHeight)
        operationView.isHidden = false
        addSubview(operationView)
        
        
        
        resetBtn = UIButton()
        resetBtn.setTitle("Reset".localized, for: .normal)
        resetBtn.setTitleColor(ColorR, for: .normal)
        resetBtn.backgroundColor = .white
        resetBtn.titleLabel?.font = Font14
        resetBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: LRSpacing)
        resetBtn.addTarget(self, action: #selector(reset), for: .touchUpInside)
        operationView.addSubview(resetBtn)
        
        /// !!! 先隐藏掉，以后版本再来添加过滤器功能
//        addToFiterBtn = UIButton()
//        addToFiterBtn.setTitle("添加到过滤器", for: .normal)
//        addToFiterBtn.setTitleColor(ColorB, for: .normal)
//        addToFiterBtn.backgroundColor = .white
//        addToFiterBtn.titleLabel?.font = Font14
//        addToFiterBtn.addTarget(self, action: #selector(addToFiter), for: .touchUpInside)
//        operationView.addSubview(addToFiterBtn)
        
        doneBtn = UIButton()
        doneBtn.setTitle("Done".localized, for: .normal)
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.titleLabel?.font = Font14
        doneBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: LRSpacing, bottom: 0, right: LRSpacing)
        doneBtn.backgroundColor = ColorSY
        doneBtn.addTarget(self, action: #selector(done), for: .touchUpInside)
        operationView.addSubview(doneBtn)
        
        let line = UIView(frame: CGRect(x: 0, y: 0, width: operationView.frame.width, height: 1))
        line.backgroundColor = ColorF
        operationView.addSubview(line)

        resetBtn.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: operationHeight)
//        resetBtn.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH / 3, height: operationHeight) // 1/3  1/5
//        addToFiterBtn.frame = CGRect(x: resetBtn.frame.maxX + 1, y: 0, width: SCREENWIDTH / 3 * 2 - 1, height: operationHeight)// 2/3  2/5
        doneBtn.frame = CGRect(x: SCREENWIDTH, y: 0, width: 0, height: operationHeight) // 0/3  2/5
        doneBtn.isHidden = true
    }
    
    func showDoneBtn(){
        doneBtn.isHidden = false
        UIView.animate(withDuration: 0.25) {
//            self.resetBtn.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH / 5, height: self.operationHeight)
//            self.addToFiterBtn.frame = CGRect(x: self.resetBtn.frame.maxX + 1, y: 0, width: SCREENWIDTH / 5 * 3 - 1, height: self.operationHeight)
//            self.doneBtn.frame = CGRect(x: self.addToFiterBtn.frame.maxX, y: 0, width: SCREENWIDTH / 5, height: self.operationHeight)
            self.resetBtn.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH / 2, height: self.operationHeight)
            self.doneBtn.frame = CGRect(x: self.resetBtn.frame.maxX, y: 0, width: SCREENWIDTH / 2, height: self.operationHeight)
        }
    }
    
    @objc func focuseBtnDidClick(btn:UIButton){
        btn.isSelected = !btn.isSelected
        if let key = btn.title(for: .disabled), let value = btn.title(for: .normal){
            if let searchKey = SearchKey(rawValue: key) {
                if btn.isSelected {
                    _focusOption.addMap(key: searchKey, values: [value])
                }else{
                    _focusOption.delete(key: searchKey, values: [value])
                }
            }
        }
        if !focusChange {
            focusChange = true
            showDoneBtn()
        }
    }
    
    func show(focuses:SearchOption){
        focusChange = false
        focusOption = focuses
        isHidden = false
        
        bgView.layer.opacity = 0
        contentView.frame = CGRect(x: 0, y: -contentHeight-operationHeight, width: SCREENWIDTH, height: contentHeight)
        operationView.frame = CGRect(x: 0, y: -operationHeight, width: SCREENWIDTH, height: operationHeight)
//        UIView.animate(withDuration: 0.15, animations: {
//            self.bgView.layer.opacity = 0.5
//        }) { (finished) in
//            if finished {
//                UIView.animate(withDuration: 0.25) {
//                    self.contentView.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: self.contentHeight)
//                    self.operationView.frame = CGRect(x: 0, y: self.contentHeight, width: SCREENWIDTH, height: self.operationHeight)
//                }
//            }
//        }
        
        UIView.animate(withDuration: 0.25) {
            self.bgView.layer.opacity = 0.5
            self.contentView.frame = CGRect(x: 0, y: 0, width: SCREENWIDTH, height: self.contentHeight)
            self.operationView.frame = CGRect(x: 0, y: self.contentHeight, width: SCREENWIDTH, height: self.operationHeight)
        }
    }
    
    @objc func hiden(){
//        UIView.animate(withDuration: 0.25, animations: {
//            self.contentView.frame = CGRect(x: 0, y: -self.contentHeight, width: SCREENWIDTH, height: self.contentHeight)
//            self.operationView.frame = CGRect(x: 0, y: -self.operationHeight, width: SCREENWIDTH, height: self.operationHeight)
//        }) { (finished) in
//            if finished {
//                UIView.animate(withDuration: 0.15, animations: {
//                    self.bgView.layer.opacity = 0
//                }) { (f) in
//                    if f {
//                        self.isHidden = true
//                    }
//                }
//            }
//        }
        UIView.animate(withDuration: 0.25, animations: {
            self.contentView.frame = CGRect(x: 0, y: -self.contentHeight, width: SCREENWIDTH, height: self.contentHeight)
            self.operationView.frame = CGRect(x: 0, y: -self.operationHeight, width: SCREENWIDTH, height: self.operationHeight)
            self.bgView.layer.opacity = 0
        }) { (finished) in
            if finished {
                self.isHidden = true
            }
        }
        delegate?.focusViewDidHiden()
    }
    
    @objc func done(){
        delegate?.focusViewDidFocuse(focuseOption: focusOption)
    }
    
    @objc func reset(){
        focusOption.removeAll()
        delegate?.focusViewDidFocuse(focuseOption: focusOption)
    }
    
    @objc func addToFiter(){
        delegate?.focusViewAddToFiter(focuseOption: focusOption)
    }
    
}
