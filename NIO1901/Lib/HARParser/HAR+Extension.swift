//
//  HAR+Extension.swift
//  NIO1901
//
//  Created by LiuJie on 2019/6/4.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import TunnelServices

extension HAR{
    func getHeaders(headDic:[String:String]) -> ([Header],[Cookie]) {
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
    
    func append(session:Session){
        
        var startTime = Date()
        let startTimeInterval = session.startTime?.doubleValue
        if startTimeInterval != nil { startTime = Date(timeIntervalSince1970: startTimeInterval!) }
        // startedDateTime
        let startedDateTime = startTime.iso8601
        // time
        let endTimeInterval = session.rspEndTime?.doubleValue
        var time = (endTimeInterval ?? 0) * 1000 - (startTimeInterval ?? 0) * 1000
        if time < 0 { time = 0}
        // request => method url httpVersion cookies reqHeaders headersSize bodySize
        let method = session.methods ?? ""
        let uri = session.getFullUrl()  // 全url
        let httpVersion = session.reqHttpVersion ?? ""
        var cookies = [Cookie]()
        var reqHeaders = [Header]()
        var headersSize:Int = -1
        var bodySize:Int = -1
        if let reqHeads = session.reqHeads {
            var headDic = Dictionary<String, String>.fromJson(reqHeads)
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
            let lastPart = uriParts[1]
            // TODO:1125:URLEncodedFormParser缺失
//            if let form = try? URLEncodedFormParser().parse(lastPart) {
//                for kv in form {
//                    queryString.append(QueryString(name: kv.key, value: kv.value.description))
//                }
//            }
        }
        let request = Request(method: method, url: uri, httpVersion: httpVersion, cookies: cookies, headers: reqHeaders, queryString: queryString, headersSize: headersSize, bodySize: bodySize)
        // request => postData bodySize
        let mimeType = session.reqType
        let ss = mimeType.components(separatedBy: "boundary=")
        var boundary:String?
        if ss.count > 1 {
            boundary = ss.last!.components(separatedBy: ";").first
        }
        var params:[Param]? = nil
        var reqText:String? = nil
        if let reqBodyData = session.getDecodedBody(true) {
            if let dataStr = String(data: reqBodyData, encoding: .utf8) { // 文本数据
                if boundary != nil { //Multipart
                    // TODO:1125:MultipartParser缺失
//                    if let parts = try? MultipartParser().parse(data: dataStr, boundary: boundary!) {
//                        params = [Param]()
//                        for part in parts {
//                            let param = Param(name: part.name ?? "")  // TODO:文件名与data 有点乱
//                            param.contentType = part.contentType?.description
//                            param.fileName = part.filename
//                            param.value = part.data
//                            params!.append(param)
//                        }
//                    }
                }else{ // text
                    reqText = dataStr
                }
            }else{ // 非文本数据
                // TODO:非文本数据有待研究
            }
            let postData = PostData(mimeType: mimeType, params: params, text: reqText)
            request.postData = postData
        }
        // response
        var status:Int?
        if let stateStr = session.state {
            status = Int(stateStr)
        }
        var response = Response()
        if status != nil {
            let statusText = session.rspMessage ?? ""
            let httpVersion = session.rspHttpVersion ?? ""
            var rspCookies = [Cookie]()
            var rspHeaders = [Header]()
            var rspHeadersSize:Int = -1
            var rspBodySize:Int = -1
            var redirectURL = ""
            if let rspHeads = session.rspHeads {
                var headDic = Dictionary<String, String>.fromJson(rspHeads)
                for kv in headDic {
                    rspHeadersSize = rspHeadersSize + kv.key.count + kv.value.count + 2 // "key: value"
                }
                if let contentLength = headDic["Content-Length"] {
                    rspBodySize = Int(contentLength) ?? 0
                }else{
                    rspBodySize = Int(session.getBodySize())
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
                content = Content(size: rspBodySize, mimeType: session.rspType)
                let bodyFileSize = Int(session.getBodySize())
                if let rspData = session.getDecodedBody() {
                    let compression = rspData.count - bodyFileSize
                    if compression > 0 { content.compression = compression }
                    if let dataStr = String(data: rspData, encoding: .utf8) {
                        content.text = dataStr
                    }else {
                        content.text = rspData.base64EncodedString()
                        content.encoding = "base64"
                    }
                }
            }
            response = Response(status: status!, statusText: statusText, httpVersion: httpVersion, cookies: rspCookies, headers: rspHeaders, content: content, redirectURL: redirectURL, headersSize: rspHeadersSize, bodySize: rspBodySize)
        }
        let cache = Cache()
        // 计算时间
        var sendTime:Double = -1
        if let connectedTime = session.connectedTime , let reqEndTime = session.reqEndTime {
            sendTime = reqEndTime.doubleValue - connectedTime.doubleValue
            sendTime = sendTime * 1000
        }
        var waitTime:Double = -1
        if let reqEndTime = session.reqEndTime , let rspStartTime = session.rspStartTime {
            waitTime = rspStartTime.doubleValue - reqEndTime.doubleValue
            waitTime = waitTime * 1000
        }
        var receiveTime:Double = -1
        if let rspStartTime = session.rspStartTime , let rspEndTime = session.rspEndTime {
            receiveTime = rspEndTime.doubleValue - rspStartTime.doubleValue
            receiveTime = receiveTime * 1000
        }
        var blockedTime:Double = -1
        if let startTime = session.startTime,let connectTime = session.connectTime {
            blockedTime = connectTime.doubleValue - startTime.doubleValue
            blockedTime = blockedTime * 1000
        }
        var connectTime:Double = -1
        if let cTime = session.connectTime,let connectedTime = session.connectedTime{
            connectTime = connectedTime.doubleValue - cTime.doubleValue
            connectTime = connectTime * 1000
        }
        let dnsTime = -1
        var sslTime:Double = -1
        if session.schemes?.lowercased() == "https" {
            if let connectedTime = session.connectedTime,let handshakeEndTime = session.handshakeEndTime {
                sslTime = handshakeEndTime.doubleValue - connectedTime.doubleValue
                sslTime = sslTime * 1000
            }
        }
        let timings = Timings(send: Int(sendTime), wait: Int(waitTime), receive: Int(receiveTime))
        timings.blocked = Int(blockedTime)
        timings.connect = Int(connectTime)
        timings.dns = Int(dnsTime)
        timings.ssl = Int(sslTime)
        
        
        let serverIPAddress = session.getRemoteIPAddress()
        let entry = Entry(startedDateTime: startedDateTime, time: Int(time), request: request, response: response, cache: cache, timings: timings, serverIPAddress: serverIPAddress)
        log.entries.append(entry)
    }
}
