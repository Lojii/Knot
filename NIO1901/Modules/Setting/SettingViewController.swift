//
//  SettingViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/24.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import MessageUI
import AxLogger

class SettingViewController: BaseViewController {

    var currentNet:String = ""
    let setRows = ["HTTPS CA certificate Settings".localized,"Feedback bugs or advice".localized,"Terms & Conditions".localized,"Privacy Policy".localized,"About".localized]
    
    // tableView
    lazy var tableView: UITableView = {
        let tableViewFrame = CGRect(x: 0, y: NAVGATIONBARHEIGHT, width: SCREENWIDTH, height: SCREENHEIGHT - NAVGATIONBARHEIGHT)
        let tableView = UITableView(frame: tableViewFrame, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SettingCell.self, forCellReuseIdentifier: "SettingCell")
        tableView.separatorStyle = .none
        tableView.rowHeight = 55
        return tableView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navTitle = "Settings".localized
        
        Nan.loadNan() // 难
        setupUI()
        // 网络监控
        NotificationCenter.default.addObserver(self, selector: #selector(networkChanged(note:)), name: NetWorkChangedNoti, object: nil)
    }
    
    func setupUI(){
        view.addSubview(tableView)
    }
    
    @objc func networkChanged(note: Notification) {
        if let reachability = note.object as? String {
            currentNet = reachability
        }
    }
    
    func sendMail() {
        
        let systemVersion = AxEnvHelper.systemVersion()
        let platform = AxEnvHelper.platform()
        let appVersion = AxEnvHelper.appVersion()
        
        let subject = "Knot-\(appVersion)"
        let describe = "Please describe the problems or advice.".localized
        let info = "\n\n\n\n\n\n\n\n\n\nKnot\(appVersion) \(platform) \(systemVersion) \(currentNet)"
        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.delegate = self
            mail.mailComposeDelegate = self
            mail.setToRecipients([CONNECTEMAIL])
            mail.setMessageBody(describe + info, isHTML: false)
            mail.setSubject(subject)
            mail.modalPresentationStyle = .fullScreen
            present(mail, animated: true)
        } else {
            let alertController = UIAlertController(title: "Send e-mail".localized, message: "Send email to".localized + CONNECTEMAIL, preferredStyle: .alert)
            let copyAction = UIAlertAction(title: "Copy email address".localized, style: .default) { (aa) in
                let pasteboard = UIPasteboard.general
                pasteboard.string = CONNECTEMAIL
                ZKProgressHUD.showMessage("Copy success".localized)
            }
            let configMailAction = UIAlertAction(title: "Send with system mail".localized, style: .default) { (aa) in
                let body = (describe + info).toUrlEncoded() ?? ""
                let urlStr = "mailto:\(CONNECTEMAIL)?subject=\(subject.toUrlEncoded() ?? "")&body=\(body)"
                print("URLSTR:\(urlStr)")
                if let mailUrl = URL(string: urlStr) {
                    if UIApplication.shared.canOpenURL(mailUrl) {
                        UIApplication.shared.openURL(mailUrl)
                    }else{
                        print("无法发送")
                    }
                }else{
                    print("转换URL失败")
                }
            }
            let alertAction = UIAlertAction(title: "Cancel".localized, style: .cancel, handler: nil)
            alertController.addAction(copyAction)
            alertController.addAction(configMailAction)
            alertController.addAction(alertAction)
            self.present(alertController, animated: true)
        }
    }
}

extension SettingViewController: MFMailComposeViewControllerDelegate,UINavigationControllerDelegate {
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        switch result {
        case .cancelled:
            ZKProgressHUD.showMessage("Cancelled".localized)
        case .saved:
            ZKProgressHUD.showMessage("Draft saved".localized)
        case .sent:
            ZKProgressHUD.showMessage("Send success".localized)
        case .failed:
            guard let error = error else { return }
            ZKProgressHUD.showMessage("\("Send failure".localized)\(error.localizedDescription)")
            print("Failed to send mail. Reason \(error.localizedDescription)")
        @unknown default:
            break
        }
        controller.dismiss(animated: true, completion: nil)
    }
    
}

extension SettingViewController:UITableViewDelegate,UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Nan.isNan() ? setRows.count : (setRows.count - 1)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingCell") as! SettingCell
        if Nan.isNan() {
            cell.nameLabel.text = setRows[indexPath.row]
        }else{
            cell.nameLabel.text = setRows[indexPath.row + 1]
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if Nan.isNan() {
            if indexPath.row == 0 {
                navigationController?.pushViewController(CertificateViewController(), animated: true)
            }
            if indexPath.row == 1 {
                sendMail()
            }
            if indexPath.row == 2 {
                let wvc = WebViewController()
                wvc.type = "TC"
                navigationController?.pushViewController(wvc, animated: true)
            }
            if indexPath.row == 3 {
                let wvc = WebViewController()
                wvc.type = "PP"
                navigationController?.pushViewController(wvc, animated: true)
            }
            if indexPath.row == 4 {
                navigationController?.pushViewController(AboutViewController(), animated: true)
            }
        }else{
            if indexPath.row == 0 {
                sendMail()
            }
            if indexPath.row == 1 {
                let wvc = WebViewController()
                wvc.type = "TC"
                navigationController?.pushViewController(wvc, animated: true)
            }
            if indexPath.row == 2 {
                let wvc = WebViewController()
                wvc.type = "PP"
                navigationController?.pushViewController(wvc, animated: true)
            }
            if indexPath.row == 3 {
                navigationController?.pushViewController(AboutViewController(), animated: true)
            }
        }
        
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
}


class SettingCell:UITableViewCell {
    
    var nameLabel:UILabel
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.nameLabel = UILabel.initWith(color: ColorB, font: Font16, text: "", frame: CGRect.zero)
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
        nameLabel.numberOfLines = 1
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { (m) in
            m.top.bottom.equalToSuperview()
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing)
        }
        let line = UIView()
        line.backgroundColor = ColorE
        contentView.addSubview(line)
        line.snp.makeConstraints { (m) in
            m.left.equalToSuperview().offset(LRSpacing)
            m.right.equalToSuperview().offset(-LRSpacing)
            m.bottom.equalToSuperview()
            m.height.equalTo(1)
        }
    }
}
