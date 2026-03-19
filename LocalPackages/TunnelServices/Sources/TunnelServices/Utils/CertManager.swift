//
//  CertManager.swift
//  TunnelServices
//
//  Standalone certificate manager that owns all certificate state
//  (CA cert, private key, cert pool) independently of CaptureTask/ASModel.
//

import Foundation
import NIOSSL
import X509
import _CryptoExtras

public class CertManager {

    // NIOSSL types (for TLS handlers)
    public let cacert: NIOSSLCertificate?
    public let cakey: NIOSSLPrivateKey?
    public let rsakey: NIOSSLPrivateKey?

    // swift-certificates types (for cert generation)
    public let x509CACert: Certificate?
    public let rsaSigningKey: _RSA.Signing.PrivateKey?

    // Thread-safe per-host certificate cache
    public let certPool: ThreadSafeCertPool

    /// Whether all required certificates and keys loaded successfully.
    public var isValid: Bool {
        cacert != nil && cakey != nil && rsakey != nil && x509CACert != nil && rsaSigningKey != nil
    }

    /// Load certificates from the app group cert directory via CertStore.
    public init() {
        let store = CertStore()
        self.cacert = store.cacert
        self.cakey = store.cakey
        self.rsakey = store.rsakey
        self.x509CACert = store.x509CACert
        self.rsaSigningKey = store.rsaSigningKey
        self.certPool = ThreadSafeCertPool()

        if !store.isValid {
            AxLogger.log("CertManager: some certificates failed to load", level: .Error)
        }
    }
}
