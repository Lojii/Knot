//
//  RuleCell.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/7.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan

class RuleCell: UITableViewCell {

    var detailHandler:((Rule) -> Void)?
    var nameLabel:UILabel
    var detailLable:UILabel
    var effectBGView:UIView = UIView()
    var _rule:Rule?
    var rule: Rule? {
        get { return _rule }
        set {
            _rule = newValue
            nameLabel.text = _rule?.name
            if let note = _rule?.note, note == "" {
                detailLable.text = _rule?.create_time
            }else{
                detailLable.text = _rule?.note
            }
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.nameLabel = UILabel()
        self.detailLable = UILabel()
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func awakeFromNib() {
        super.awakeFromNib()

    }

    func setupUI(){

        let sbgView = UIView()
        let hidenLabel = UILabel()
        hidenLabel.textColor = ColorA
        hidenLabel.font = Font16
        hidenLabel.text = "      "
        sbgView.addSubview(hidenLabel)
        hidenLabel.snp.makeConstraints { (m) in
            m.bottom.equalTo(sbgView.snp.centerY)
            m.left.equalToSuperview().offset(LRSpacing * 2)
        }
        let checkIcon = UIView()
        checkIcon.backgroundColor = ColorSG
        checkIcon.layer.cornerRadius = LRSpacing / 2
        checkIcon.clipsToBounds = true
        sbgView.addSubview(checkIcon)
        checkIcon.snp.makeConstraints { (m) in
            m.centerY.equalTo(hidenLabel.snp.centerY)
            m.height.width.equalTo(LRSpacing)
            m.left.equalToSuperview().offset(LRSpacing)
        }
        effectBGView.backgroundColor = .black
        effectBGView.alpha = 0
        effectBGView.isHidden = true
        sbgView.addSubview(effectBGView)
        effectBGView.snp.makeConstraints { (m) in
            m.width.height.top.left.equalToSuperview()
        }
        selectedBackgroundView = sbgView



        nameLabel.textColor = ColorA
        nameLabel.font = Font16
        detailLable.textColor = ColorB
        detailLable.font = Font12
        let infoBtn = UIButton(type: .infoLight)
        infoBtn.addTarget(self, action: #selector(infoBtnDidClick), for: .touchUpInside)
        contentView.addSubview(infoBtn)
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailLable)

        infoBtn.snp.makeConstraints { (m) in
            m.centerY.equalToSuperview()
            m.right.equalToSuperview()//.offset(-LRSpacing)
            m.width.height.equalTo(contentView.snp.height)
        }
        nameLabel.snp.makeConstraints { (m) in
            m.bottom.equalTo(contentView.snp.centerY)
            m.left.equalToSuperview().offset(LRSpacing)
        }
        detailLable.snp.makeConstraints { (m) in
            m.top.equalTo(contentView.snp.centerY).offset(3)
            m.left.equalToSuperview().offset(LRSpacing)
        }

        let line = UIView()
        line.backgroundColor = ColorF
        addSubview(line)
        line.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing + 5)
            m.right.equalToSuperview().offset(-LRSpacing)
            m.bottom.equalToSuperview()
            m.height.equalTo(1)
        }

    }

    @objc func infoBtnDidClick(){
        detailHandler?(rule!)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        nameLabel.snp.updateConstraints { (m) in
            m.bottom.equalTo(contentView.snp.centerY)
            m.left.equalToSuperview().offset(selected ? LRSpacing * 2 + 5 : LRSpacing)
        }
        if selected {
            effectBGView.isHidden = false
            effectBGView.alpha = 0
            UIView.animate(withDuration: 0.2, animations: {
                self.effectBGView.alpha = 0.2
            }) { (finised) in
                if finised {
                    UIView.animate(withDuration: 0.2, animations: {
                        self.effectBGView.alpha = 0
                    }, completion: { (f) in
                        if f {
                            self.effectBGView.isHidden = true
                        }
                    })
                }
            }
        }
    }
}
