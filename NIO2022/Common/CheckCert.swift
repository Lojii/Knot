//
//  CheckCert.swift
//  NIO2022
//
//  Created by LiuJie on 2022/3/28.
//

import UIKit
import CocoaHTTPServer
import NIOMan
import Alamofire

public enum TrustResultType:String {
//    case nofond = "nofond"
    case none = "none"
    case installed = "installed"
    case trusted = "trusted"
}

public class CheckCert {
    
//    public static let shared = CheckCert()
    
    var sslServer:HTTPServer?
    var _checkCallBack:((TrustResultType) -> Void)?
    var checkCallBack: ((TrustResultType) -> Void)? {
        get {
            return _checkCallBack
        }
        set {
            _checkCallBack = newValue
            if _checkCallBack == nil {
                if (sslServer != nil) {
                    sslServer?.stop()
                    sslServer = nil
                }
            }
        }
    }
    let port: Int = 4433
    
    public init() {
        
    }
    
    deinit {
        // 释放资源
        print("CheckCert deinit !")
    }
    
    public static func checkPermissions(_ callBack:@escaping (TrustResultType) -> Void){
        let check = CheckCert()//.shared
        check.isTrust(callBack)
    }
    
    public func isTrust(_ callBack:@escaping (TrustResultType) -> Void){
        checkCallBack = callBack
        // 先检查本地是否存在证书
        
        
        // 先检查是否安装证书
        let certPath = NIOMan.CertPath()?.appendingPathComponent("CA.cert.pem")
        let str = try? String(contentsOf: certPath!)
        var strs = str?.components(separatedBy: "\n")
        strs?.removeFirst()
        strs?.removeLast()
        strs?.removeLast()
        let fullStr = strs?.joined(separator: "") ?? ""
        if let pemcert = Data(base64Encoded: fullStr), let cert = SecCertificateCreateWithData(nil, pemcert as CFData) {
            // Check
            var secTrust: SecTrust?
            if SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &secTrust) == errSecSuccess, let trust = secTrust {
                if #available(iOS 13.0, *) {
                    SecTrustEvaluateAsyncWithError(trust, .main) { trust, result, error in
                        if !result {
                            if (self.checkCallBack != nil) {
                                self.checkCallBack!(.none)
                                self.checkCallBack = nil
                            }
                        }else{
                            self.checkTrust()
                        }
                    }
                } else {
                    var trustResult: SecTrustResultType = .invalid
                    _ = SecTrustEvaluate(trust, &trustResult)
                    if trustResult != .proceed && trustResult != .unspecified {
                        if (checkCallBack != nil) {
                            checkCallBack!(.none)
                            checkCallBack = nil
                        }
                    }else{
                        self.checkTrust()
                    }
                }
            }
        }else{
            if (checkCallBack != nil) {
//                checkCallBack!(.nofond)
                checkCallBack!(.none)
                checkCallBack = nil
            }
        }
    }
    
    func checkTrust(){
        // 启动ssl服务，检查是否信任证书
        sslServer = HTTPServer()
        sslServer?.setPort(UInt16(port))
        sslServer?.setType("_http._tcp.")
        let webRootPath = NIOMan.CertPath()
        sslServer?.setDocumentRoot(webRootPath?.path.components(separatedBy: "file://").last)
        sslServer?.setConnectionClass(LocalSSLHttpConnection.self)
        try? sslServer?.start()
//        let timeStr = Date().timeIntervalSince1970  ?timeStr=\(timeStr)
        Alamofire.request("https://127.0.0.1:\(port)" , method: .get, parameters: nil, headers: nil).response { rsp in
            if (self.checkCallBack == nil) { return }
            if(rsp.response?.statusCode == 200){ self.checkCallBack!(.trusted) }else{ self.checkCallBack!(.installed) }
            self.checkCallBack = nil
        }
    }
}

class LocalSSLHttpConnection:HTTPConnection{
    
    override func isSecureServer() -> Bool {
        return true
    }
    
    override func sslIdentityAndCertificates() -> [Any]! {
        NIOMan.updateSelfSignedCert()
        if let p12Path = NIOMan.CertPath()?.appendingPathComponent("\(Date().yearSting).self.p12") {
            do {
                let p12 = try Data(contentsOf: p12Path) as CFData
                let options = [kSecImportExportPassphrase as String: "123"] as CFDictionary
                var rawItems: CFArray?
                guard SecPKCS12Import(p12, options, &rawItems) == errSecSuccess else {
                    print("Error in p12 import")
                    return []
                }

                let items = rawItems as! Array<Dictionary<String,Any>>
                let identity = items[0][kSecImportItemIdentity as String] as! SecIdentity
                var certificate:SecCertificate? = nil
                SecIdentityCopyCertificate(identity, &certificate)
                return [identity, certificate as Any]
            }
            catch {
                print("Could not create server certificate")
                return []
            }
        }
        return []
    }
}
