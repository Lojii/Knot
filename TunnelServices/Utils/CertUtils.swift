//
//  CertUtils.swift
//  NIO1901
//
//  Created by LiuJie on 2019/4/21.
//  Copyright © 2019 Lojii. All rights reserved.
//

import UIKit
import NIO
import CNIOBoringSSL
import NIOSSL

public class CertUtils: NSObject {
    
//    static let shared = CertUtils()
//
//    var certPool:[String:NIOSSLCertificate]?
    
//    public func certFree(){
//        for cert in certPool.values {
//            CNIOBoringSSL_X509_free(cert.ref)
//        }
//        certPool.removeAll()
//    }
    
//    public override init() {
//        certPool = [String:NIOSSLCertificate]()
//    }
    
    
    public static func generateRSAPrivateKey() -> UnsafeMutablePointer<EVP_PKEY> {
        let exponent = CNIOBoringSSL_BN_new()
        defer {
            CNIOBoringSSL_BN_free(exponent)
        }
        
        CNIOBoringSSL_BN_set_u64(exponent, 0x10001)
        
        let rsa = CNIOBoringSSL_RSA_new()!
        let generateRC = CNIOBoringSSL_RSA_generate_key_ex(rsa, CInt(2048), exponent, nil)
        precondition(generateRC == 1)
        
        let pkey = CNIOBoringSSL_EVP_PKEY_new()!
        let assignRC = CNIOBoringSSL_EVP_PKEY_assign(pkey, EVP_PKEY_RSA, rsa)
        
        precondition(assignRC == 1)
        return pkey
    }
    
    public static func generateCert(host:String, rsaKey:NIOSSLPrivateKey, caKey: NIOSSLPrivateKey, caCert: NIOSSLCertificate) -> NIOSSLCertificate {
//        if let result = shared.certPool?[host] {
//            return result
//        }
        let caPriKey = caKey._ref.assumingMemoryBound(to: EVP_PKEY.self)
        let req = CNIOBoringSSL_X509_REQ_new()
        let key:UnsafeMutablePointer<EVP_PKEY> = rsaKey._ref.assumingMemoryBound(to: EVP_PKEY.self)//generateRSAPrivateKey()
        /* Set the public key. */
        CNIOBoringSSL_X509_REQ_set_pubkey(req, key)
        /* Set the DN of the request. */
        let name = CNIOBoringSSL_X509_NAME_new()
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "C", MBSTRING_ASC, "SE", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "ST", MBSTRING_ASC, "", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "L", MBSTRING_ASC, "", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "O", MBSTRING_ASC, "Company", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "OU", MBSTRING_ASC, "", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, host, -1, -1, 0);
        CNIOBoringSSL_X509_REQ_set_subject_name(req, name)
        /* Self-sign the request to prove that we posses the key. */
        CNIOBoringSSL_X509_REQ_sign(req, key, CNIOBoringSSL_EVP_sha256())
        /* Sign with the CA. */
        let crt = CNIOBoringSSL_X509_new() // nil?
        /* Set version to X509v3 */
        CNIOBoringSSL_X509_set_version(crt, 2)
        /* Generate random 20 byte serial. */
        let serial = Int(arc4random_uniform(UInt32.max))
//        print("生成一次随机数-------")
        CNIOBoringSSL_ASN1_INTEGER_set(CNIOBoringSSL_X509_get_serialNumber(crt), serial)
//        serial = 0
        /* Set issuer to CA's subject. */
        // TODO:1125:这句也会报错！fix
        CNIOBoringSSL_X509_set_issuer_name(crt, CNIOBoringSSL_X509_get_subject_name(caCert._ref.assumingMemoryBound(to: X509.self)))
        /* Set validity of certificate to 1 years. */
        let notBefore = CNIOBoringSSL_ASN1_TIME_new()!
        var now = time(nil)
        CNIOBoringSSL_ASN1_TIME_set(notBefore, now)
        let notAfter = CNIOBoringSSL_ASN1_TIME_new()!
        now += 86400 * 365
        CNIOBoringSSL_ASN1_TIME_set(notAfter, now)
        CNIOBoringSSL_X509_set_notBefore(crt, notBefore)
        CNIOBoringSSL_X509_set_notAfter(crt, notAfter)
        CNIOBoringSSL_ASN1_TIME_free(notBefore)
        CNIOBoringSSL_ASN1_TIME_free(notAfter)
        /* Get the request's subject and just use it (we don't bother checking it since we generated it ourself). Also take the request's public key. */
        CNIOBoringSSL_X509_set_subject_name(crt, name)
        let reqPubKey = CNIOBoringSSL_X509_REQ_get_pubkey(req)
        CNIOBoringSSL_X509_set_pubkey(crt, reqPubKey)
        CNIOBoringSSL_EVP_PKEY_free(reqPubKey)
        
        // 满足iOS13要求. See https://support.apple.com/en-us/HT210176
        addExtension(x509: crt!, nid: NID_basic_constraints, value: "critical,CA:FALSE")
        addExtension(x509: crt!, nid: NID_ext_key_usage, value: "serverAuth,OCSPSigning")
        addExtension(x509: crt!, nid: NID_subject_key_identifier, value: "hash")
        addExtension(x509: crt!, nid: NID_subject_alt_name, value: "DNS:" + host)
        
        /* Now perform the actual signing with the CA. */
        CNIOBoringSSL_X509_sign(crt, caPriKey, CNIOBoringSSL_EVP_sha256())
        CNIOBoringSSL_X509_REQ_free(req)

//        CNIOBoringSSL_EVP_PKEY_CTX_dup(key)
//        let copyCrt = CNIOBoringSSL_X509_dup(crt!)!
//        shared.certPool?[host] = NIOSSLCertificate.fromUnsafePointer(takingOwnership: copyCrt)
        let copyCrt2 = CNIOBoringSSL_X509_dup(crt!)!
        //
        let cert = NIOSSLCertificate.fromUnsafePointer(takingOwnership: copyCrt2)
//        let cert = try! NIOSSLCertificate(file: "", format: .pem)
        CNIOBoringSSL_X509_free(crt!)
        return cert
    }

    public static func addExtension(x509: UnsafeMutablePointer<X509>, nid: CInt, value: String) {
        var extensionContext = X509V3_CTX()
        
        CNIOBoringSSL_X509V3_set_ctx(&extensionContext, x509, x509, nil, nil, 0)
        let ext = value.withCString { (pointer) in
            return CNIOBoringSSL_X509V3_EXT_nconf_nid(nil, &extensionContext, nid, UnsafeMutablePointer(mutating: pointer))
        }!
        CNIOBoringSSL_X509_add_ext(x509, ext, -1)
        CNIOBoringSSL_X509_EXTENSION_free(ext)
    }
}
