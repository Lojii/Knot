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
    
    public static func genreateCert(host: String, rsaKeyPEM: Data, caKeyPEM: Data, caCertPEM: Data) -> NIOSSLCertificate {
        var bp = rsaKeyPEM.withUnsafeBytes({ ptr -> UnsafeMutablePointer<BIO> in
            let pointer = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return CNIOBoringSSL_BIO_new_mem_buf(pointer, Int32(rsaKeyPEM.count))
        })
        var rsaKey = CNIOBoringSSL_EVP_PKEY_new()
        defer {CNIOBoringSSL_EVP_PKEY_free(rsaKey)}
        CNIOBoringSSL_PEM_read_bio_PrivateKey(bp, &rsaKey, nil, nil)
        CNIOBoringSSL_BIO_free(bp)
        
        bp = caKeyPEM.withUnsafeBytes({ ptr -> UnsafeMutablePointer<BIO> in
            let pointer = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return CNIOBoringSSL_BIO_new_mem_buf(pointer, Int32(caKeyPEM.count))
        })
        var caKey = CNIOBoringSSL_EVP_PKEY_new()
        defer {CNIOBoringSSL_EVP_PKEY_free(caKey)}
        CNIOBoringSSL_PEM_read_bio_PrivateKey(bp, &caKey, nil, nil)
        CNIOBoringSSL_BIO_free(bp)
        
        bp = caCertPEM.withUnsafeBytes({ ptr -> UnsafeMutablePointer<BIO> in
            let pointer = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            return CNIOBoringSSL_BIO_new_mem_buf(pointer, Int32(caCertPEM.count))
        })
        let caCert = CNIOBoringSSL_PEM_read_bio_X509(bp, nil, nil, nil)
        CNIOBoringSSL_BIO_free(bp)
        
        let req = CNIOBoringSSL_X509_REQ_new()
        defer { CNIOBoringSSL_X509_REQ_free(req) }
        CNIOBoringSSL_X509_REQ_set_pubkey(req, rsaKey)
        
        let name = CNIOBoringSSL_X509_NAME_new()
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "C", MBSTRING_ASC, "SE", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "ST", MBSTRING_ASC, "", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "L", MBSTRING_ASC, "", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "O", MBSTRING_ASC, "Company", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "OU", MBSTRING_ASC, "", -1, -1, 0);
        CNIOBoringSSL_X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, host, -1, -1, 0);
        CNIOBoringSSL_X509_REQ_set_subject_name(req, name)
        CNIOBoringSSL_X509_REQ_sign(req, rsaKey, CNIOBoringSSL_EVP_sha256())
        
        let cert = CNIOBoringSSL_X509_new()
        defer {CNIOBoringSSL_X509_free(cert)}
        CNIOBoringSSL_X509_set_version(cert, 2)
        let serial = Int(arc4random_uniform(UInt32.max))
        CNIOBoringSSL_ASN1_INTEGER_set(CNIOBoringSSL_X509_get_serialNumber(cert), serial)
        CNIOBoringSSL_X509_set_issuer_name(cert, CNIOBoringSSL_X509_get_subject_name(caCert))
        
        let notBefore = CNIOBoringSSL_ASN1_TIME_new()!
        var now = time(nil)
        CNIOBoringSSL_ASN1_TIME_set(notBefore, now)
        let notAfter = CNIOBoringSSL_ASN1_TIME_new()
        now += 86400 * 365
        CNIOBoringSSL_ASN1_TIME_set(notAfter, now)
        CNIOBoringSSL_X509_set1_notBefore(cert, notBefore)
        CNIOBoringSSL_X509_set1_notAfter(cert, notAfter)
        CNIOBoringSSL_ASN1_TIME_free(notBefore)
        CNIOBoringSSL_ASN1_TIME_free(notAfter)
        CNIOBoringSSL_X509_set_subject_name(cert, name)
        
        let reqPubkey = CNIOBoringSSL_X509_REQ_get_pubkey(req)
        CNIOBoringSSL_X509_set_pubkey(cert, reqPubkey)
        CNIOBoringSSL_EVP_PKEY_free(reqPubkey)
        
        addExtension(x509: cert!, nid: NID_basic_constraints, value: "critical,CA:FALSE")
        addExtension(x509: cert!, nid: NID_ext_key_usage, value: "serverAuth,OCSPSigning")
        addExtension(x509: cert!, nid: NID_subject_key_identifier, value: "hash")
        addExtension(x509: cert!, nid: NID_subject_alt_name, value: "DNS:" + host)
        
        CNIOBoringSSL_X509_sign(cert, caKey, CNIOBoringSSL_EVP_sha256())
        
        /// X509 -> Data -> [UInt8] -> NIOSSLCertificate
        let out = CNIOBoringSSL_BIO_new(CNIOBoringSSL_BIO_s_mem())!
        defer {CNIOBoringSSL_BIO_free(out)}
        CNIOBoringSSL_PEM_write_bio_X509(out, cert)
        var ptr: UnsafeMutableRawPointer?
        let len = CNIOBoringSSL_BIO_ctrl(out, BIO_CTRL_INFO, 0, &ptr)
        let buffer = Data(bytes: ptr!, count: len)

        return try! NIOSSLCertificate(bytes: [UInt8](buffer), format: .pem)
    }
    
    private static func addExtension(x509: OpaquePointer, nid: CInt, value: String) {
        var extensionContext = X509V3_CTX()
        
        CNIOBoringSSL_X509V3_set_ctx(&extensionContext, x509, x509, nil, nil, 0)
        let ext = value.withCString { (pointer) in
            return CNIOBoringSSL_X509V3_EXT_nconf_nid(nil, &extensionContext, nid, UnsafeMutablePointer(mutating: pointer))
        }
        CNIOBoringSSL_X509_add_ext(x509, ext, -1)
        CNIOBoringSSL_X509_EXTENSION_free(ext)
    }
}
