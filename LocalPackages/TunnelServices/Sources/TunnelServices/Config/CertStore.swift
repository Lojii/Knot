//
//  CertStore.swift
//  TunnelServices
//
//  Centralized certificate and key loading.
//  Eliminates duplicated loadCACert() across CaptureTask and SSLServer.
//

import Foundation
import NIOSSL
import X509
import _CryptoExtras

public class CertStore {

    public let cacert: NIOSSLCertificate?
    public let cakey: NIOSSLPrivateKey?
    public let rsakey: NIOSSLPrivateKey?
    public let x509CACert: Certificate?
    public let rsaSigningKey: _RSA.Signing.PrivateKey?
    /// The CA private key as swift-crypto type (for signing leaf certs in CertGenerator).
    public let caSigningKey: _RSA.Signing.PrivateKey?

    public var isValid: Bool {
        cacert != nil && cakey != nil && rsakey != nil && x509CACert != nil && rsaSigningKey != nil && caSigningKey != nil
    }

    public init() {
        guard let certDir = CertStore.certDirectoryURL() else {
            cacert = nil; cakey = nil; rsakey = nil; x509CACert = nil; rsaSigningKey = nil; caSigningKey = nil
            return
        }

        let certPath = CertStore.filePath(in: certDir, name: ProxyConfig.CertFiles.caCert)
        let keyPath = CertStore.filePath(in: certDir, name: ProxyConfig.CertFiles.caKey)
        let rsaPath = CertStore.filePath(in: certDir, name: ProxyConfig.CertFiles.rsaKey)

        // Auto-generate CA on first launch if cert files don't exist
        if !FileManager.default.fileExists(atPath: certPath) {
            CertStore.generateAndSave(certDir: certDir)
        }

        cacert = try? NIOSSLCertificate(file: certPath, format: .pem)
        cakey = try? NIOSSLPrivateKey(file: keyPath, format: .pem)
        rsakey = try? NIOSSLPrivateKey(file: rsaPath, format: .pem)
        x509CACert = try? CertGenerator.loadCertificate(fromPEMFile: certPath)
        rsaSigningKey = try? CertGenerator.loadRSAPrivateKey(fromPEMFile: rsaPath)
        caSigningKey = try? CertGenerator.loadRSAPrivateKey(fromPEMFile: keyPath)
    }

    /// Generate CA cert + keys and save to cert directory. Called once on first launch.
    private static func generateAndSave(certDir: URL) {
        do {
            let (caCert, caKey, rsaKey) = try CertGenerator.generateCA()

            // Save CA cert as PEM
            let certPEM = try CertGenerator.toPEM(caCert)
            try certPEM.write(toFile: filePath(in: certDir, name: ProxyConfig.CertFiles.caCert),
                              atomically: true, encoding: .utf8)

            // Save CA cert as DER (for iOS profile install)
            let certDER = try CertGenerator.toDER(caCert)
            try certDER.write(to: certDir.appendingPathComponent(ProxyConfig.CertFiles.caCertDER))

            // Save CA private key as PEM
            let caKeyPEM = caKey.pemRepresentation
            try caKeyPEM.write(toFile: filePath(in: certDir, name: ProxyConfig.CertFiles.caKey),
                               atomically: true, encoding: .utf8)

            // Save RSA key as PEM (used for per-host dynamic cert generation)
            let rsaKeyPEM = rsaKey.pemRepresentation
            try rsaKeyPEM.write(toFile: filePath(in: certDir, name: ProxyConfig.CertFiles.rsaKey),
                                atomically: true, encoding: .utf8)

            AxLogger.log("CertStore: CA certificate generated and saved to \(certDir.path)", level: .Info)
        } catch {
            AxLogger.log("CertStore: failed to generate CA: \(error)", level: .Error)
        }
    }

    // MARK: - Path Helpers

    public static func certDirectoryURL() -> URL? {
        let fileManager = FileManager.default
        guard var certDir = fileManager.containerURL(forSecurityApplicationGroupIdentifier: ProxyConfig.appGroupIdentifier) else {
            return nil
        }
        certDir.appendPathComponent(ProxyConfig.Storage.certFolder)
        let dirPath = certDir.path
        if !fileManager.fileExists(atPath: dirPath) {
            try? fileManager.createDirectory(at: certDir, withIntermediateDirectories: true, attributes: nil)
        }
        return certDir
    }

    static func filePath(in dir: URL, name: String) -> String {
        dir.appendingPathComponent(name, isDirectory: false).path
    }
}
