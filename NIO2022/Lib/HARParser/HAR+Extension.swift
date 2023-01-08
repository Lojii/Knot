//
//  HAR+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/4.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIOMan

extension HAR{
    static func getHeaders(headDic:[String:String]) -> ([Header],[Cookie]) {
        var dic = headDic
        var cookies = [Cookie]()
        var headers = [Header]()
        // TODO:1125:HTTPCookies缺失
//        if let cookieValue = dic["Cookie"], let httpCookie = HTTPCookies.parse(cookieHeader: cookieValue) {
//            for kv in httpCookie.all{
//                let value = kv.value
//                let name = kv.key
//                let cookie = Cookie(name: name, value: value.string)
//                cookie.domain = value.domain
//                cookie.path = value.path
//                cookie.maxAge = value.maxAge
//                cookie.sameSite = value.sameSite.map { $0.rawValue }
//                if let expires = value.expires { cookie.expires = expires.iso8601 } // formatter.string(from: expires)
//                if value.isHTTPOnly { cookie.httpOnly = true }
//                if value.isSecure { cookie.secure = true }
//                cookies.append(cookie)
//            }
//        }
        dic.removeValue(forKey: "Cookie")
        for kv in dic { headers.append(Header(name: kv.key, value: kv.value)) }
        return (headers,cookies)
    }
    
    static func entry(session:Session) -> Entry?{
        
        _ = session.syncParse()
        
        var startTime = Date()
        let startTimeInterval = session.dns_time_s.doubleValue
        startTime = Date(timeIntervalSince1970: startTimeInterval)
        // startedDateTime
        let startedDateTime = startTime.iso8601
        // time
        let endTimeInterval = session.receive_e.doubleValue
        var time = endTimeInterval * 1000 - startTimeInterval * 1000
        if time < 0 { time = 0}
        // request => method url httpVersion cookies reqHeaders headersSize bodySize
        let method = session.method
        let uri = session.fullUrl()  // 全url
        let httpVersion = session.version
        var cookies = [Cookie]()
        var reqHeaders = [Header]()
        var headersSize:Int = -1
        var bodySize:Int = -1
        if let headDic = session.head() {
            for kv in headDic {
                headersSize = headersSize + kv.key.count + kv.value.count + 2 // "key: value"
            }
            if let contentLength = headDic["Content-Length"] {
                bodySize = Int(contentLength) ?? -1
            }
            let cr = getHeaders(headDic: headDic)
            cookies = cr.1
            reqHeaders = cr.0
        }
        // request => queryString
        var queryString = [QueryString]()
        let uriParts = uri.components(separatedBy: "?")
        if uriParts.count == 2 {
//            let lastPart = uriParts[1]
            // TODO:1125:URLEncodedFormParser缺失
//            if let form = try? URLEncodedFormParser().parse(lastPart) {
//                for kv in form {
//                    queryString.append(QueryString(name: kv.key, value: kv.value.description))
//                }
//            }
        }
        let request = Request(method: method, url: uri, httpVersion: httpVersion, cookies: cookies, headers: reqHeaders, queryString: queryString, headersSize: headersSize, bodySize: bodySize)
        // request => postData bodySize
        let mimeType = session.req_content_type
        let ss = mimeType.components(separatedBy: "boundary=")
        var boundary:String?
        if ss.count > 1 {
            boundary = ss.last!.components(separatedBy: ";").first
        }
        var params:[Param]? = nil
        var reqText:String? = nil
        if let reqBodyPath = session.body(true) {
            if let reqBodyUrl = URL(string: "file://\(reqBodyPath)"), let reqBody = try? Data(contentsOf: reqBodyUrl) {
                if let bodyStr = String(data: reqBody, encoding: .utf8) { // 文本数据
                    if boundary != nil { //Multipart
                        // TODO:1125:MultipartParser缺失
//                        if let parts = try? MultipartParser().parse(data: dataStr, boundary: boundary!) {
//                            params = [Param]()
//                            for part in parts {
//                                let param = Param(name: part.name ?? "")  // TODO:文件名与data 有点乱
//                                param.contentType = part.contentType?.description
//                                param.fileName = part.filename
//                                param.value = part.data
//                                params!.append(param)
//                            }
//                        }
                    }else{ // text
                        reqText = bodyStr
                    }
                }else{ // 非文本数据
                    // TODO:非文本数据有待研究
                }
                let postData = PostData(mimeType: mimeType, params: params, text: reqText)
                request.postData = postData
            }
        }
        
        // response
        var status:Int?
        if "" != session.rsp_state {
            status = Int(session.rsp_state)
        }
        var response = Response()
        if status != nil {
            let statusText = session.rsp_message
            let httpVersion = session.version
            var rspCookies = [Cookie]()
            var rspHeaders = [Header]()
            var rspHeadersSize:Int = -1
            var rspBodySize:Int = -1
            var redirectURL = ""
            if let headDic = session.head(false) {
                for kv in headDic {
                    rspHeadersSize = rspHeadersSize + kv.key.count + kv.value.count + 2 // "key: value"
                }
                if let contentLength = headDic["Content-Length"] {
                    rspBodySize = Int(contentLength) ?? 0
                }else{
                    if let attr = try? FileManager.default.attributesOfItem(atPath: session.body(false) ?? "") {
                        let dict = attr as NSDictionary
                        rspBodySize = Int(dict.fileSize())
                    }
                }
                if let location = headDic["Location"] {
                    redirectURL = location
                }
                let cr = getHeaders(headDic: headDic)
                rspCookies = cr.1
                rspHeaders = cr.0
            }

            var content = Content(size: 0, mimeType: "")
            if rspBodySize > 0 {
                content = Content(size: rspBodySize, mimeType: session.rsp_content_type)
                var bodyFileSize = 0
                if let attr = try? FileManager.default.attributesOfItem(atPath: session.body(false) ?? "") {
                    let dict = attr as NSDictionary
                    bodyFileSize = Int(dict.fileSize())
                }
                if let rspBodyPath = session.body(false) {
                    if let rspBodyUrl = URL(string: "file://"+rspBodyPath), var rspData = try? Data(contentsOf: rspBodyUrl) {
                        // 如果type为gzip\br\... 则尝试解压
                        if session.rsp_encode.lowercased().contains("gzip") ||
                            session.rsp_encode.lowercased().contains("deflate") ||
                            session.rsp_encode.lowercased().contains("br") ||
                            session.rsp_encode.lowercased().contains("compress"){
                            if let unZipData = rspData.gunzip() {rspData = unZipData
                            }else if let unZipData = rspData.unzip() {rspData = unZipData
                            }else if let unZipData = rspData.inflate() {rspData = unZipData
                            }else if let unZipData = NSData(data: rspData).decompressBrotli() {rspData = unZipData
                            }else if let unZipData = rspData.decompress(withAlgorithm: .zlib) {rspData = unZipData
                            }else if let unZipData = rspData.decompress(withAlgorithm: .lz4) {rspData = unZipData
                            }else if let unZipData = rspData.decompress(withAlgorithm: .lzfse) {rspData = unZipData
                            }else if let unZipData = rspData.decompress(withAlgorithm: .lzma) {rspData = unZipData
                            }
                        }
//                        if rspData.count > 800000000 { // 大于800兆的文件，不予处理
//                            content.text = "The file is too large."
//                        }else{
                            let compression = rspData.count - bodyFileSize
                            if compression > 0 { content.compression = compression }
                            if let dataStr = String(data: rspData, encoding: .utf8) {
                                content.text = dataStr
                            }else {
                                content.text = rspData.base64EncodedString()
                                content.encoding = "base64"
                            }
//                        }
                    }
                }
            }
            response = Response(status: status!, statusText: statusText, httpVersion: httpVersion, cookies: rspCookies, headers: rspHeaders, content: content, redirectURL: redirectURL, headersSize: rspHeadersSize, bodySize: rspBodySize)
        }
        let cache = Cache()
        // 时间
        // 排队时间
        let blockedTime = -1
        // DNS时间
        var dnsTime:Double = (session.connect_s.doubleValue - session.dns_time_s.doubleValue) * 1000
        if dnsTime <= 0 { dnsTime = -1 }
        // 连接时间
        var connectTime:Double = (session.send_s.doubleValue - session.connect_s.doubleValue) * 1000
        if connectTime <= 0 { connectTime = -1 }
        // 发送时间
        var sendTime:Double = (session.send_e.doubleValue - session.send_s.doubleValue) * 1000
        if sendTime <= 0 { sendTime = -1 }
        // 等待时间
        var waitTime:Double = (session.receive_s.doubleValue - session.send_e.doubleValue) * 1000
        if waitTime <= 0 { waitTime = -1 }
        // 接收时间
        var receiveTime:Double = (session.receive_e.doubleValue - session.receive_s.doubleValue) * 1000
        if receiveTime <= 0 { receiveTime = -1 }
        let sslTime:Double = -1
        
        let timings = Timings(send: Int(sendTime), wait: Int(waitTime), receive: Int(receiveTime))
        timings.blocked = Int(blockedTime)
        timings.dns = Int(dnsTime)
        timings.connect = Int(connectTime)
        timings.ssl = Int(sslTime)

        let serverIPAddress = session.dsthost_str
        let entry = Entry(startedDateTime: startedDateTime, time: Int(time), request: request, response: response, cache: cache, timings: timings, serverIPAddress: serverIPAddress)
        return entry
    }
    
    func append(session:Session){
        if let e = HAR.entry(session: session) {
            log.entries.append(e)
        }
    }
}
