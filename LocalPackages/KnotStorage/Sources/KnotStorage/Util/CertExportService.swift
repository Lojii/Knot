//
//  CertExportService.swift
//  KnotStorage
//
//  Saves and exports TLS certificate PEM files.
//  NIO/X509/Crypto dependencies removed — only works with raw PEM strings and Data.
//

import Foundation

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

    /// Read a previously saved PEM file and return its content + basic summary.
    /// Note: Full X.509 parsing (subject, issuer, etc.) requires the caller to use
    /// swift-certificates or NIOSSL in the proxy layer.
    public func exportCertChain(certChainRef: String) -> Swift.Result<CertExportResult, CertExportError> {
        let fullPath = (fileFolder as NSString).appendingPathComponent(certChainRef)
        guard FileManager.default.fileExists(atPath: fullPath) else {
            return .failure(.fileNotFound(fullPath))
        }
        do {
            let pem = try String(contentsOfFile: fullPath, encoding: .utf8)
            // Count certificate blocks as a basic summary
            var summaries = [[String: String]]()
            let blocks = pem.components(separatedBy: "-----END CERTIFICATE-----")
            for (index, block) in blocks.enumerated() {
                guard block.range(of: "-----BEGIN CERTIFICATE-----") != nil else { continue }
                summaries.append(["index": "\(index)"])
            }
            return .success(CertExportResult(pemText: pem, summary: summaries))
        } catch {
            return .failure(.parseFailed(error.localizedDescription))
        }
    }
}
