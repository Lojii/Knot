//
//  CertExportNIO.swift
//  TunnelServices
//
//  Bridge between NIOSSL certificates and KnotStorage's CertExportService.
//  Converts NIOSSLCertificate → PEM string, then delegates to CertExportService.
//

import Foundation
import NIOSSL
import X509
import SwiftASN1
import Crypto
import KnotStorage

public enum CertExportNIOBridge {

    /// Convert NIOSSLCertificates to PEM, save via CertExportService, and return ref + summary.
    public static func saveCertChain(
        certService: CertExportService,
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
        let ref = try certService.savePEMString(flowId: flowId, pemContent: pemContent)
        return (ref, summaries)
    }
}
