//
//  SettingViewController.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/24.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import MessageUI
import FileBrowser
import UIKit
import NIOMan
import Alamofire
//import SwiftyStoreKit

class SettingViewController: BaseViewController {

    var currentNet:String = ""
    
    var rows =  [
        ["title":"HTTPS CA certificate Settings".localized,     "type":"ca"],
//        ["title":"More Happy".localized,                        "type":"happy"],
//        ["title":"Restore".localized,                           "type":"restore"],
        ["title":"Feedback bugs or advice".localized,           "type":"bugs"],
        ["title":"Terms & Conditions".localized,                "type":"tc"],
        ["title":"Privacy Policy".localized,                    "type":"pp"],
        ["title":"About".localized,                             "type":"about"],
    ]
    
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
        
//        Nan.loadNan() // 难
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
        
        let systemVersion = ""//AxEnvHelper.systemVersion()
        let platform = "iOS"
        let appVersion = "0.8.0"//AxEnvHelper.appVersion()

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
                        UIApplication.shared.open(mailUrl)
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
    func rowHandle(row:Dictionary<String, Any>){
        if let type = row["type"] as? String{
            if type == "ca" {
                navigationController?.pushViewController(CertificateViewController(), animated: true)
            }
            if type == "happy" {
                if KnotPurchase.check(.HappyKnot){
                    ZKProgressHUD.showMessage("Have to buy".localized)
                }else{
                    KnotPurchase.check(.HappyKnot) { res in
                        
                    }
                }
            }
            if type == "restore" {
                ZKProgressHUD.show()
                KnotPurchase.restore(purchaseProduct: nil) { res in
                    DispatchQueue.main.async{
                    ZKProgressHUD.dismiss()
                    if res {
                        ZKProgressHUD.showMessage("Success".localized)
                    }else{
                        ZKProgressHUD.showMessage("Restore failure".localized)
                    }
                    }
                }
            }
            if type == "bugs" {
                sendMail()
//                DispatchQueue.global().async{
//                    let time = Date().timeIntervalSince1970
//                    let taskId = String(format: "%.0f", time)
//                    let gud = UserDefaults(suiteName: GROUPNAME)
//                    gud?.set(taskId, forKey: CURRENTTASKID)
//                    gud?.synchronize()
//                    let res = NIOMan.run(taskId: taskId)
//                    if res == 0 {
//                        gud?.removeObject(forKey: CURRENTTASKID)
//                        gud?.synchronize()
//                    }
//                }
            }
            if type == "tc" {
                let wvc = WebViewController()
                wvc.type = "TC"
                navigationController?.pushViewController(wvc, animated: true)
            }
            if type == "pp" {
                let wvc = WebViewController()
                wvc.type = "PP"
                navigationController?.pushViewController(wvc, animated: true)
//                let url = URL(string: "https://cn.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1")
//                let url2 = URL(string: "http://api.asilu.com/php/web-info.php")
//                let url = URL(string: "https://www.apple.com")
//                let url = URL(string: "https://1.1.1.1")
//                let url = URL(string: "http://1.1.1.1:7888")
//                let url = URL(string: "http://[::1]:80")
//                let url = URL(string: "http://statuse.digitalcertvalidation.com/MFYwVKADAgEAME0wSzBJMAkGBSsOAwIaBQAEFEmsXTFgDj2MLcPzd%2BAMZ6xpSTMhBBR%2F05nzoEcOMQBWViKOt8ye3coBigIQAt%2B%2BPDwoXITYDgzEc8AHHQ%3D%3D")
//                let url = URL(string: "https://47.99.112.78/1.0/comments/listPrimary")
//                var header = HTTPHeaders()
//                header["Host"] = "api.ruguoapp.com"
//                Alamofire.request(url! , method: .get, parameters: nil, headers: header).response { rsp in
//                    print("请求完成 url")
//                }
//                Alamofire.request(url2! , method: .get, parameters: nil, headers: nil).response { rsp in
//                    print("请求完成 url2")
//                }
//                let url = URL(string: "https://api.pinduoduo.com/api/caterham/query/subfenlei_gyl_label?opt_id=109&offset=20&req_list_action_type=0&page_id=catgoods.html&list_id=109_2635455107&count=20&opt_type=2&content_goods_num=4&page_sn=10028&engine_version=2.0&support_types=0_4&pdduid=3942732346")
//                var header = HTTPHeaders()
//                header["x-b3-ptracer"] = "52C93B035E294FE8874B2414A773F2ED"
//                header["rctk-sign"] = "9Ne0BDgzkPaKUk4wVaePr8jClckEnYlWxV86NniZ9Rs="
//                header["vip"] = "81.69.104.49"
//                header["Cookie"] = "api_uid=CiEZYGI1JsGxtwBjuX6WAg=="
//                header["X-PDD-QUERIES"] = "width=1125.000000&height=2436.000000&brand=apple&model=iPhone X&osv=15.3.1&appv=6.6.0&pl=iOS&net=1"
//                header["PDD-CONFIG"] = "V4:002.060600"
//                header["multi-set"] = "1,2"
//                header["lat"] = "237AQL6F6PEIYN2RD2LCLZQQCH5L2YQI3U5SXQMJXJD6TLXPBMUQ1123a47"
//                header["p-proc-time"] = "277140"
//                header["AccessToken"] = "237AQL6F6PEIYN2RD2LCLZQQCH5L2YQI3U5SXQMJXJD6TLXPBMUQ1123a47"
//                header["anti-token"] = "1abLHCCZluXdX4s90YT+cPjmGn3mQlSJigbpBfzlAawyhuePy1MGgye+KIAAtWJ7j1y589NsUN3lQrLX9Nz9F7CLRe8VFdiwfPY75xNP/yS1H3d1lAiFQ8mZYWEqDOTKePt7aFMtozCaVykxy1KLKsS79hIUV7pvf+d58aFgVpnEu/WhWOHKT5Kd0I/wdAxhPH3RA5488ESMsPtmOSAXYnysLNkgjX1AbBX+nvE6Xtxhaxhy9dgNB6elNEJDyz9lrPtXtyoTGSli3xqqBefH5PVSo5EtS5n/sfzlyfiWz/pxt7BxsWLAXbkW+vtB3rLiPtSl0UXNOb49Ty6VUp6MAeYelMCvI5XqAWKWAvjNa8FBJ+q0qXihmxUDCpOCg6yyLMRjj3hgSU2+AOHt7HjwHcynoyoiPaaXftuLyFJ4A58vbg="
//                header["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 === iOS/15.3.1 Model/iPhone10,3 BundleID/com.xunmeng.pinduoduo AppVersion/6.6.0 AppBuild/202203282237 pversion/2400 cURL/7.75.0"
//                header["Host"] = "api.pinduoduo.com"
//                header["x-yak-llt"] = "1649519417000"
//                header["Etag"] = "pH15SXVb"
//                header["p-appname"] = "pinduoduo"
//                header["rctk"] = "rctk_plat=com.xunmeng.pinduoduo.ios&rctk_ver=6.6.0&rctk_ts=1650026823698&rctk_nonce=F1004E02ED544CEF9F3433B0255BCC3A&rctk_rpkg=0"
//                Alamofire.request(url! , method: .get, parameters: nil, headers: header).response { rsp in
//                    print("请求完成 url")
//                }
            }
            if type == "about" {
                navigationController?.pushViewController(AboutViewController(), animated: true)
//                let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
//                let fileBrowser = FileBrowser(initialPath: directory, allowEditing: true, showCancelButton: true)
//                fileBrowser.modalPresentationStyle = .fullScreen
//                present(fileBrowser, animated: true, completion: nil)
            }
        }
    }
}

extension SettingViewController:UITableViewDelegate,UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingCell") as! SettingCell
        cell.nameLabel.text = rows[indexPath.row]["title"] ?? ""
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = rows[indexPath.row]
        rowHandle(row: row)
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
