//
//  SearchHistoryView.swift
//  NIO1901
//
//  Created by LiuJie on 2019/5/27.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

let SearchHistoryDidUpdateNoti = NSNotification.Name.init(rawValue: "SearchHistoryDidUpdateNoti")
let SearchHistoryUserDefaults = "SearchHistoryUserDefaults"

protocol SearchHistoryViewDelegate: class {
    func historyDidClick(history:String)
}

class SearchHistoryView: UIView {
    
    weak var deleage:SearchHistoryViewDelegate?
    
    var _historys:[String] = [String]()
    var historys: [String] {
        get { return _historys }
        set {
            _historys = newValue
            initUI()
        }
    }
    var scrollView:UIScrollView
    
    init(delegate:SearchHistoryViewDelegate?) {
        self.deleage = delegate
        self.scrollView = UIScrollView()
        super.init(frame: CGRect.zero)
        addSubview(scrollView)
        scrollView.snp.makeConstraints { (m) in
            m.center.width.height.equalToSuperview()
        }
        
        initUI()
        // 获取历史记录
        searchHistoryDidUpdate()
        NotificationCenter.default.addObserver(self, selector: #selector(searchHistoryDidUpdate), name: SearchHistoryDidUpdateNoti, object: nil)
    }
    
//    override init(frame: CGRect) {
//
//        self.scrollView = UIScrollView()
//        super.init(frame: frame)
//        addSubview(scrollView)
//        scrollView.snp.makeConstraints { (m) in
//            m.center.width.height.equalToSuperview()
//        }
//
//        initUI()
//        // 获取历史记录
//        searchHistoryDidUpdate()
//        NotificationCenter.default.addObserver(self, selector: #selector(searchHistoryDidUpdate), name: SearchHistoryDidUpdateNoti, object: nil)
//    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func initUI(){
        for v in scrollView.subviews {
            v.removeFromSuperview()
        }
        
        var offY:CGFloat = 0
        let iconWH:CGFloat = 15
        let textW:CGFloat = SCREENWIDTH - LRSpacing * 2 - 30 - iconWH - 10
        let textFont = Font16
        
        for i in 0..<historys.count {
            let history = historys[historys.count - 1 - i]
            let textH = history.textHeight(font: textFont, fixedWidth: textW) + 20
            let itemView = UIView(frame: CGRect(x: 0, y: offY, width: SCREENWIDTH, height: textH))
            itemView.tag = historys.count - 1 - i
            itemView.isUserInteractionEnabled = true
            itemView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(historyDidClick(tap:))))
            // icon
            let iconView = UIImageView(image: UIImage(named: "search_history"))
            iconView.frame = CGRect(x: LRSpacing, y: (textH - iconWH) / 2, width: iconWH, height: iconWH)
            itemView.addSubview(iconView)
            // label
            let label = UILabel(frame: CGRect(x: iconView.frame.maxX + 10, y: 0, width: textW, height: textH))
            label.numberOfLines = 0
            label.font = textFont
            label.textColor = ColorC
            label.text = history
            itemView.addSubview(label)
            // delete
            let deleteBtn = UIButton(frame: CGRect(x: label.frame.maxX , y: 0, width: SCREENWIDTH - label.frame.maxX - 5, height: textH))
            deleteBtn.setImage(UIImage(named: "close-1"), for: .normal)
            deleteBtn.tag = i
            deleteBtn.addTarget(self, action: #selector(delectHistory(sender:)), for: .touchUpInside)
            itemView.addSubview(deleteBtn)
            // line
            if i != historys.count - 1 {
                let lineView = UIView(frame: CGRect(x: LRSpacing, y: label.frame.maxY, width: SCREENWIDTH - LRSpacing * 2, height: 1))
                lineView.backgroundColor = ColorF
                itemView.addSubview(lineView)
            }
            offY = offY + textH
            scrollView.addSubview(itemView)
        }
        let clearBtn = UIButton(frame: CGRect(x: SCREENWIDTH / 4, y: offY + 10, width: SCREENWIDTH / 2, height: 40))
        clearBtn.setTitle("Clear history".localized, for: .normal)
        clearBtn.setTitleColor(ColorC, for: .normal)
        clearBtn.titleLabel?.font = Font14
        clearBtn.addTarget(self, action: #selector(clearHistory), for: .touchUpInside)
        scrollView.addSubview(clearBtn)
        offY = offY + clearBtn.frame.height + 10
        scrollView.contentSize = CGSize(width: 0, height: offY)
    }
    
    @objc func historyDidClick(tap:UIGestureRecognizer){
        if let tag = tap.view?.tag {
            deleage?.historyDidClick(history: "\(historys[tag])")
        }
    }
    
    @objc func searchHistoryDidUpdate(){
        historys = UserDefaults.standard.stringArray(forKey: SearchHistoryUserDefaults) ?? [String]()
    }
    
    @objc func delectHistory(sender:UIButton){
        let tag = sender.tag
        if historys.count > tag {
            historys.remove(at: tag)
        }
        let defaults = UserDefaults.standard
        defaults.set(historys, forKey: SearchHistoryUserDefaults)
        defaults.synchronize()
        NotificationCenter.default.post(name: SearchHistoryDidUpdateNoti, object: nil)
    }
    
    @objc func clearHistory(){
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SearchHistoryUserDefaults)
        defaults.synchronize()
        NotificationCenter.default.post(name: SearchHistoryDidUpdateNoti, object: nil)
    }
}

extension SearchHistoryView: JXSegmentedListContainerViewListDelegate {
    func listView() -> UIView {
        return self
    }
}
