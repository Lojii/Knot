//
//  DownloadTools.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/12.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit

class DownloadTools: NSObject,URLSessionDownloadDelegate {
    
    static let shared = DownloadTools()
    
    var url:URL?
    var progress: ((CGFloat) -> Void)?
    var complete: ((Data?,URL) -> Void)?
    var failure: ((String) -> Void)?

    private lazy var session:URLSession = {
        //只执行一次
        let config = URLSessionConfiguration.default
        let currentSession = URLSession(configuration: config, delegate: self,
                                        delegateQueue: nil)
        return currentSession
        
    }()
    
    static func down(url:URL,progress:@escaping ((CGFloat) -> Void), complete:@escaping ((Data?,URL) -> Void), failure:@escaping ((String) -> Void)){
        shared.url = url
        shared.progress = progress
        shared.complete = complete
        shared.failure = failure
        
        shared.sessionSeniorDownload()
    }
    
    //下载文件
    func sessionSeniorDownload(){
        let request = URLRequest(url: url!)
        let downloadTask = session.downloadTask(with: request)
        downloadTask.resume()
    }
    
    //下载代理方法，下载结束
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        //输出下载文件原来的存放目录
        if complete != nil {
            let data = try? Data(contentsOf: location)
            complete?(data,location)
        }
    }
    
    //下载代理方法，监听下载进度
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        //获取进度
        let written:CGFloat = (CGFloat)(totalBytesWritten)
        let total:CGFloat = (CGFloat)(totalBytesExpectedToWrite)
        let pro:CGFloat = written/total
        progress?(pro)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            failure?(error?.localizedDescription ?? "")
        }
    }
    
}
