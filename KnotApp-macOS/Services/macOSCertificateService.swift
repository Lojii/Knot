import Foundation
import Security
import KnotCore
import TunnelServices

/// macOS certificate service.
/// Uses Security framework to install the CA into the system keychain
/// and set explicit trust for SSL.
final class macOSCertificateService: CertificateServiceProtocol {

    private(set) var trustStatus: CertTrustStatus = .notInstalled
    private var localServer: MitmService?

    init() {
        _ = checkTrustStatus()
    }

    // MARK: - CertificateServiceProtocol

    func installCertificate() async throws {
        guard let certDir = MitmService.getCertPath() else {
            throw CertError.certNotFound
        }
        let certFileURL = certDir.appendingPathComponent(ProxyConfig.CertFiles.caCertDER)
        guard FileManager.default.fileExists(atPath: certFileURL.path) else {
            throw CertError.certNotFound
        }
        let certData = try Data(contentsOf: certFileURL)
        guard let certRef = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw CertError.invalidCertData
        }

        // Add to system keychain
        let addQuery: [String: Any] = [
            kSecClass as String:            kSecClassCertificate,
            kSecValueRef as String:         certRef,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw CertError.keychainError(addStatus)
        }

        // Set explicit trust for SSL
        let trustSettings: [[String: Any]] = [
            [
                kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, nil),
                kSecTrustSettingsResult as String: Int(SecTrustSettingsResult.trustAsRoot.rawValue),
            ]
        ]
        let trustStatus = SecTrustSettingsSetTrustSettings(certRef, .user, trustSettings as CFTypeRef)
        guard trustStatus == errSecSuccess else {
            throw CertError.keychainError(trustStatus)
        }

        _ = checkTrustStatus()
    }

    func exportCertificate() -> Data {
        guard let certDir = MitmService.getCertPath() else { return Data() }
        let certFileURL = certDir.appendingPathComponent(ProxyConfig.CertFiles.caCertDER)
        return (try? Data(contentsOf: certFileURL)) ?? Data()
    }

    @discardableResult
    func checkTrustStatus() -> CertTrustStatus {
        guard let certDir = MitmService.getCertPath() else {
            trustStatus = .notInstalled
            return trustStatus
        }
        let certFileURL = certDir.appendingPathComponent(ProxyConfig.CertFiles.caCertDER)
        guard let certData = try? Data(contentsOf: certFileURL),
              let certRef = SecCertificateCreateWithData(nil, certData as CFData) else {
            trustStatus = .notInstalled
            return trustStatus
        }

        var trustSettingsArray: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certRef, .user, &trustSettingsArray)

        if status == errSecSuccess, let settings = trustSettingsArray, CFArrayGetCount(settings) > 0 {
            trustStatus = .trusted
        } else if status == errSecItemNotFound {
            // Cert may be installed but not trusted yet
            trustStatus = .installed
        } else {
            trustStatus = .notInstalled
        }
        return trustStatus
    }

    func startLocalServer(port: Int) async throws {
        guard let service = MitmService.prepare() else {
            throw CertError.serverStartFailed
        }
        localServer = service
        return try await withCheckedThrowingContinuation { continuation in
            service.openLocalServer(ip: ProxyConfig.LocalProxy.host, port: port) { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let e): continuation.resume(throwing: e)
                }
            }
        }
    }

    func stopLocalServer() {
        localServer?.closeLocalServer()
        localServer = nil
    }
}

enum CertError: Error {
    case certNotFound
    case invalidCertData
    case keychainError(OSStatus)
    case serverStartFailed
}
