//
//  CertExportService.swift
//  TunnelServices
//
//  Saves and exports TLS certificate chains as PEM files.
//

import Foundation
import NIOSSL
import X509
import SwiftASN1
import Crypto

public final class CertExportService {
    private let fileFolder: String

    public init(fileFolder: String) {
        self.fileFolder = fileFolder
    }

    // MARK: - Save

    /// Save a raw PEM string to disk and return the relative path reference.
    public func savePEMString(flowId: String, pemContent: String) throws -> String {
        let relPath = "certs/\(flowId).pem"
        let dir = (fileFolder as NSString).appendingPathComponent("certs")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let fullPath = (fileFolder as NSString).appendingPathComponent(relPath)
        try pemContent.write(toFile: fullPath, atomically: true, encoding: .utf8)
        return relPath
    }

    /// Convert NIOSSLCertificates to PEM, save to disk, and return the reference + summary.
    public func saveCertChain(
        flowId: String,
        certificates: [NIOSSLCertificate]
    ) throws -> (ref: String, summary: [[String: String]]) {
        var pemParts = [String]()
        var summaries = [[String: String]]()

        for cert in certificates {
            let derBytes = try cert.toDERBytes()
            let base64 = Data(derBytes).base64EncodedString(options: .lineLength64Characters)
            pemParts.append("-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----\n")

            let x509 = try Certificate(derEncoded: derBytes)
            summaries.append([
                "subject": x509.subject.description,
                "issuer": x509.issuer.description,
                "serial": x509.serialNumber.description,
                "sha256": SHA256.hash(data: Data(derBytes)).map { String(format: "%02x", $0) }.joined(),
                "notBefore": "\(x509.notValidBefore)",
                "notAfter": "\(x509.notValidAfter)",
            ])
        }

        let pemContent = pemParts.joined()
        let ref = try savePEMString(flowId: flowId, pemContent: pemContent)
        return (ref, summaries)
    }

    // MARK: - Export

    public struct CertExportResult {
        public let pemText: String
        public let summary: [[String: String]]
    }

    public enum CertExportError: Error {
        case noCertChain
        case fileNotFound(String)
        case parseFailed(String)
    }

    /// Read a previously saved PEM file and return its content + parsed summary.
    public func exportCertChain(certChainRef: String) -> Result<CertExportResult, CertExportError> {
        let fullPath = (fileFolder as NSString).appendingPathComponent(certChainRef)
        guard FileManager.default.fileExists(atPath: fullPath) else {
            return .failure(.fileNotFound(fullPath))
        }
        do {
            let pem = try String(contentsOfFile: fullPath, encoding: .utf8)
            var summaries = [[String: String]]()
            let blocks = pem.components(separatedBy: "-----END CERTIFICATE-----")
            for block in blocks {
                guard let range = block.range(of: "-----BEGIN CERTIFICATE-----") else { continue }
                let base64 = block[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if let derData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                    if let x509 = try? Certificate(derEncoded: Array(derData)) {
                        summaries.append([
                            "subject": x509.subject.description,
                            "issuer": x509.issuer.description,
                        ])
                    }
                }
            }
            return .success(CertExportResult(pemText: pem, summary: summaries))
        } catch {
            return .failure(.parseFailed(error.localizedDescription))
        }
    }
}
