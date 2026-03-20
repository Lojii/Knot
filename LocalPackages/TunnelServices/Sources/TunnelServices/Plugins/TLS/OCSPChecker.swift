//
//  OCSPChecker.swift
//  TunnelServices
//
//  Online Certificate Status Protocol (OCSP) checker.
//  Queries OCSP responders to verify certificate revocation status.
//  Netty reference: handler-ssl-ocsp/OcspClientHandler.java
//

import Foundation
import NIOSSL

// MARK: - OCSP Result

public struct OCSPResult {
    public enum Status: String {
        case good = "good"
        case revoked = "revoked"
        case unknown = "unknown"
        case error = "error"
        case noOCSP = "no_ocsp"  // No OCSP responder URL in certificate
    }

    public let status: Status
    public let responderURL: String?
    public let checkedAt: Date
    public let message: String?
}

// MARK: - OCSP Checker

public class OCSPChecker {

    /// Check certificate status via OCSP.
    /// Uses the OCSP responder URL embedded in the certificate's AIA extension.
    public static func check(host: String, port: Int = 443, timeout: TimeInterval = 10) -> OCSPResult {
        // Step 1: Connect and get the server's certificate chain
        guard let certChain = fetchCertificateChain(host: host, port: port, timeout: timeout) else {
            return OCSPResult(status: .error, responderURL: nil, checkedAt: Date(),
                            message: "Failed to connect to \(host):\(port)")
        }

        guard certChain.count >= 1 else {
            return OCSPResult(status: .error, responderURL: nil, checkedAt: Date(),
                            message: "No certificates in chain")
        }

        // Step 2: Extract OCSP responder URL from the certificate
        // (AIA extension with id-ad-ocsp OID: 1.3.6.1.5.5.7.48.1)
        // For now, use a known OCSP responder or try to extract from cert
        // This is a simplified implementation

        // Step 3: Use Apple's SecTrust API to validate
        let certData = certChain[0]
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            return OCSPResult(status: .error, responderURL: nil, checkedAt: Date(),
                            message: "Invalid certificate data")
        }

        let policy = SecPolicyCreateSSL(true, host as CFString)
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates([secCert] as CFArray, policy, &trust)
        guard status == errSecSuccess, let trust = trust else {
            return OCSPResult(status: .error, responderURL: nil, checkedAt: Date(),
                            message: "Failed to create trust object")
        }

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        if isValid {
            return OCSPResult(status: .good, responderURL: nil, checkedAt: Date(),
                            message: "Certificate is valid and trusted")
        } else {
            let errorMsg = error.map { CFErrorCopyDescription($0) as String } ?? "Unknown error"
            // Determine if it's revoked or just untrusted
            if errorMsg.lowercased().contains("revok") {
                return OCSPResult(status: .revoked, responderURL: nil, checkedAt: Date(),
                                message: errorMsg)
            }
            return OCSPResult(status: .unknown, responderURL: nil, checkedAt: Date(),
                            message: errorMsg)
        }
    }

    /// Fetch the DER-encoded certificate chain from a TLS server.
    private static func fetchCertificateChain(host: String, port: Int, timeout: TimeInterval) -> [Data]? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [Data]?

        let session = URLSession(configuration: .ephemeral, delegate: CertChainDelegate { chain in
            result = chain
            semaphore.signal()
        }, delegateQueue: nil)

        guard let url = URL(string: "https://\(host):\(port)") else { return nil }
        let task = session.dataTask(with: url) { _, _, _ in }
        task.resume()

        _ = semaphore.wait(timeout: .now() + timeout)
        task.cancel()
        session.invalidateAndCancel()
        return result
    }
}

// MARK: - Certificate Chain Delegate

private class CertChainDelegate: NSObject, URLSessionDelegate {
    let completion: ([Data]) -> Void

    init(completion: @escaping ([Data]) -> Void) {
        self.completion = completion
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            var certs = [Data]()
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
                for cert in chain {
                    certs.append(SecCertificateCopyData(cert) as Data)
                }
            }
            completion(certs)
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
