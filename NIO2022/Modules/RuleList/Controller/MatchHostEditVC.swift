//
//  MatchHostEditVC.swift
//  NIO2022
//
//  Created by LiuJie on 2022/4/7.
//

import UIKit
import SnapKit
import NIOMan

class MatchHostEditVC: UIViewController {
    
    var textField:UITextField!
    var hosts:[String] = []
    var tableView:UITableView!
    var doneBlock:((String?, Int) -> Void)?
    var index:Int = -1
    var value:String = ""
    
    deinit {
        print("---------- MatchHostEditVC deinit !")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white
        
        setUI()
        
        loadData()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if (doneBlock != nil) {
            doneBlock!(textField.text, index)
        }
    }
    
    func setUI(){
        let topView = UIView(frame: CGRect(x: 0, y: 0, width: SCREENWIDTH, height: 50))
        topView.backgroundColor = ColorE
        let closeBtn = UIButton()
        closeBtn.setImage(UIImage(named: "close-2"), for: .normal)
        topView.addSubview(closeBtn)
        let titleLabel = UILabel()
        titleLabel.text = "Add Host".localized
        titleLabel.font = Font18
        titleLabel.textAlignment = .center
        topView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(topView.snp_centerY)
            make.centerX.equalTo(topView.snp_centerX)
        }
        closeBtn.snp.makeConstraints { make in
            make.left.equalTo(topView.snp_left).offset(LRSpacing)
            make.width.height.equalTo(25)
            make.centerY.equalTo(titleLabel.snp_centerY)
        }
        closeBtn.isUserInteractionEnabled = true
        closeBtn.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeDidClick)))
        view.addSubview(topView)
        
        let textView = UIView(frame: CGRect(x: 0, y: topView.frame.maxY, width: SCREENWIDTH, height: 70))
        textView.backgroundColor = ColorE
        view.addSubview(textView)
        textField = UITextField(frame: CGRect(x: 0, y: 10, width: SCREENWIDTH, height: 50))
        textField.backgroundColor = .white
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 15, height: 20))
        textField.placeholder = "Matching Host".localized
        textField.leftViewMode = .always
        textField.clearButtonMode = .always
        textField.textColor = ColorB
        textField.returnKeyType = .done
        textField.addTarget(self, action: #selector(textFieldChanged(textField:)), for: .editingChanged)
        textField.text = value
        textView.addSubview(textField)
        
        tableView = UITableView(frame: CGRect.zero)
        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(textView.snp.bottom)
            make.width.equalTo(SCREENWIDTH)
            make.left.equalTo(view.snp.left)
            make.bottom.equalTo(view.snp.bottom)
        }
    }
    
    @objc func textFieldChanged(textField: UITextField){
        loadData()
    }
    
    @objc func closeDidClick(){
        dismiss(animated: true)
    }
    
    func loadData(){
        hosts = Session.findAllHost(keyWord: textField.text ?? "")
        tableView.reloadData()
    }

}


extension MatchHostEditVC: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let host = hosts[indexPath.row]
        textField.text = host
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let host = hosts[indexPath.row]
        var cell = tableView.dequeueReusableCell(withIdentifier: "cell")
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: "cell")
        }
        cell?.textLabel?.font = Font16
        cell?.textLabel?.text = host
        cell?.accessoryType = .disclosureIndicator
        return cell!
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return hosts.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }
    
}
