//
//  ViewController.swift
//  NIO2022
//
//  Created by LiuJie on 2022/3/2.
//

import UIKit
import NIOMan
import AVFoundation
import FileBrowser
import CocoaAsyncSocket

class ViewController: UIViewController, URLSessionDelegate {
    
    var status = NEManager.Status.off
    var audioPlayer: AVAudioPlayer?
    static var host = "127.0.0.1"
    static var port = 8441
    var udpSocket : GCDAsyncUdpSocket?
    
//    init(){
//
//    }
    
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        let fullWH = UIScreen.main.bounds.size
        let btn = UIButton(frame: CGRect(x: (fullWH.width - 200) / 2, y: 0, width: 200, height: 200))
        btn.setTitle("开启VPN", for: .normal)
        btn.backgroundColor = .green
        btn.titleLabel?.textColor = .white
        btn.addTarget(self, action: #selector(toWebView), for: .touchUpInside)
        view.addSubview(btn)
        
        let openBtn = UIButton(frame: CGRect(x: (fullWH.width - 200) / 2, y: 250, width: 200, height: 80))
        openBtn.setTitle("run", for: .normal)
        openBtn.backgroundColor = .blue
        openBtn.titleLabel?.textColor = .white
        openBtn.addTarget(self, action: #selector(run), for: .touchUpInside)
        view.addSubview(openBtn)
        
        let stopBtn = UIButton(frame: CGRect(x: (fullWH.width - 200) / 2, y: 380, width: 200, height: 80))
        stopBtn.setTitle("stop", for: .normal)
        stopBtn.backgroundColor = .blue
        stopBtn.titleLabel?.textColor = .white
        stopBtn.addTarget(self, action: #selector(stop), for: .touchUpInside)
        view.addSubview(stopBtn)
        
        let reopenBtn = UIButton(frame: CGRect(x: (fullWH.width - 200) / 2, y: 480, width: 200, height: 80))
        reopenBtn.setTitle("reopen", for: .normal)
        reopenBtn.backgroundColor = .blue
        reopenBtn.titleLabel?.textColor = .white
        reopenBtn.addTarget(self, action: #selector(reopen), for: .touchUpInside)
        view.addSubview(reopenBtn)
        
        let closeBtn = UIButton(frame: CGRect(x: (fullWH.width - 200) / 2, y: 580, width: 200, height: 80))
        closeBtn.setTitle("文件夹", for: .normal)
        closeBtn.backgroundColor = .gray
        closeBtn.titleLabel?.textColor = .white
        closeBtn.addTarget(self, action: #selector(showDir), for: .touchUpInside)
        view.addSubview(closeBtn)
        
        let webBtn = UIButton(frame: CGRect(x: (fullWH.width - 200) / 2, y: 680, width: 200, height: 80))
        webBtn.setTitle("Web", for: .normal)
        webBtn.backgroundColor = .gray
        webBtn.titleLabel?.textColor = .white
        webBtn.addTarget(self, action: #selector(toWeb), for: .touchUpInside)
        view.addSubview(webBtn)
        
        NEManager.shared.statusDidChangeHandler = {[weak self] status in
            self?.status = status
        }
        
        let wavFile = Bundle.main.url(forResource: "silence", withExtension: "wav")!
        try! AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        self.audioPlayer = try! AVAudioPlayer(contentsOf:wavFile)
        self.audioPlayer?.numberOfLoops = -1
        self.audioPlayer?.volume = 0.00;
        self.audioPlayer?.play()
        
        
        // UDP通讯
        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
        do{
            try udpSocket?.bind(toPort: 60001)
        }catch{
            print("udpSocket bind error:\(error.localizedDescription)")
        }
        try? udpSocket?.beginReceiving()
    }
    
    func start() -> Void {
        
    }
    
    func formatTimeStamp(time:Int ,format:String) -> String {
        let timeInterval = TimeInterval(time)
        let date = Date.init(timeIntervalSince1970: timeInterval)
        let dateFormatte = DateFormatter()
        dateFormatte.dateFormat = format
        return dateFormatte.string(from: date)
    }
    
    @objc func toWebView(){
        NEManager.shared.start { error in
            print(error.debugDescription)
        }
    }
    
    @objc func run(){
        DispatchQueue.global().async{
            let time = Date().timeIntervalSince1970
            let taskId = String(format: "%.0f", time)
            let rv = NIOMan.run(taskId: taskId)
            if rv == 0 {
                print("启动失败")
            }
        }
    }
    
    @objc func stop(){
        NIOMan.stop()
    }
    
    @objc func reopen(){
        NIOMan.reopen()
    }
    
    @objc func showDir(){
        let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GROUPNAME)
        let fileBrowser = FileBrowser(initialPath: directory, allowEditing: true, showCancelButton: true)
        fileBrowser.modalPresentationStyle = .fullScreen
        present(fileBrowser, animated: true, completion: nil)
    }
    
    @objc func toWeb(){
        let webVC = WebVC()
        self.present(webVC, animated: true, completion: nil)
    }
}

extension ViewController: GCDAsyncUdpSocketDelegate {
    func udpSocket(_ sock: GCDAsyncUdpSocket, didReceive data: Data, fromAddress address: Data, withFilterContext filterContext: Any?) {
        let jsonStr = String(data: data, encoding: .utf8) ?? ""
        let dic = [String:Any].fromJson(jsonStr ?? "")
//        print(jsonStr)
//        if dic["url"] != nil || dic[""] != nil {
////            taskView.updateTask(dic: dic)
//        }else if let state = dic["state"] {
//            if state == "close" {
//
//            }
//        }
    }
}

