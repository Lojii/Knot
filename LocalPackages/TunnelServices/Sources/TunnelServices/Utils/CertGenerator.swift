//
//  CertGenerator.swift
//  TunnelServices
//
//  Pure Swift certificate generation using apple/swift-certificates.
//  Replaces the BoringSSL-based CertUtils.
//

import Foundation
import X509
import SwiftASN1
import Crypto
import _CryptoExtras
import NIOSSL

public class CertGenerator {

    /// Generate a self-signed CA root certificate and RSA private key.
    /// Called once on first launch to create the MITM CA.
    public static func generateCA() throws -> (caCert: Certificate, caKey: _RSA.Signing.PrivateKey, rsaKey: _RSA.Signing.PrivateKey) {
        let caKey = try _RSA.Signing.PrivateKey(keySize: .bits2048)
        let rsaKey = try _RSA.Signing.PrivateKey(keySize: .bits2048)

        let subject = try DistinguishedName {
            CountryName(ProxyConfig.CertSubject.country)
            OrganizationName(ProxyConfig.CertSubject.organization)
            CommonName("Knot CA")
        }

        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            Critical(KeyUsage(keyCertSign: true, cRLSign: true))
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: caKey.publicKey.derRepresentation))
            )
        }

        let now = Date()
        let caCert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(caKey.publicKey),
            notValidBefore: now,
            notValidAfter: now.addingTimeInterval(86400 * 365 * 10), // 10 years
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(caKey)
        )

        return (caCert, caKey, rsaKey)
    }

    /// Serialize a certificate to PEM string.
    public static func toPEM(_ cert: Certificate) throws -> String {
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        let derBytes = serializer.serializedBytes
        let base64 = Data(derBytes).base64EncodedString(options: .lineLength64Characters)
        return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----\n"
    }

    /// Serialize a certificate to DER Data.
    public static func toDER(_ cert: Certificate) throws -> Data {
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
    }

    /// Generate a dynamic TLS certificate for the given host, signed by the CA.
    /// This is the core of MITM - we create a fake cert that the proxy presents to the client.
    public static func generateCert(
        host: String,
        rsaKey: _RSA.Signing.PrivateKey,
        caKey: _RSA.Signing.PrivateKey,
        caCert: Certificate
    ) throws -> Certificate {
        let subject = try DistinguishedName {
            CountryName(ProxyConfig.CertSubject.country)
            OrganizationName(ProxyConfig.CertSubject.organization)
            CommonName(host)
        }

        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.notCertificateAuthority)
            try ExtendedKeyUsage([.serverAuth, .ocspSigning])
            SubjectKeyIdentifier(
                keyIdentifier: ArraySlice(Crypto.SHA256.hash(data: rsaKey.publicKey.derRepresentation))
            )
            SubjectAlternativeNames([.dnsName(host)])
        }

        let now = Date()
        let cert = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(rsaKey.publicKey),
            notValidBefore: now,
            notValidAfter: now.addingTimeInterval(86400 * 365),
            issuer: caCert.subject,
            subject: subject,
            signatureAlgorithm: .sha256WithRSAEncryption,
            extensions: extensions,
            issuerPrivateKey: Certificate.PrivateKey(caKey)
        )

        return cert
    }

    /// Convert a swift-certificates Certificate to NIOSSLCertificate (for TLS handler use).
    public static func toNIOSSL(_ cert: Certificate) throws -> NIOSSLCertificate {
        var serializer = DER.Serializer()
        try cert.serialize(into: &serializer)
        let derBytes = serializer.serializedBytes
        return try NIOSSLCertificate(bytes: derBytes, format: .der)
    }

    /// Load a Certificate from a PEM file (using swift-certificates).
    public static func loadCertificate(fromPEMFile path: String) throws -> Certificate {
        let pemString = try String(contentsOfFile: path, encoding: .utf8)
        return try Certificate(pemEncoded: pemString)
    }

    /// Load an RSA private key from a PEM file.
    public static func loadRSAPrivateKey(fromPEMFile path: String) throws -> _RSA.Signing.PrivateKey {
        let pemString = try String(contentsOfFile: path, encoding: .utf8)
        return try _RSA.Signing.PrivateKey(pemRepresentation: pemString)
    }
}
