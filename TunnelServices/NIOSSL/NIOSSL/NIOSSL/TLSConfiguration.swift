//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.1) && compiler(<5.2)
@_implementationOnly import CNIOBoringSSL
#else
import CNIOBoringSSL
#endif
import NIO

/// Known and supported TLS versions.
public enum TLSVersion {
    case tlsv1
    case tlsv11
    case tlsv12
    case tlsv13
}

/// Places NIOSSL can obtain certificates from.
public enum NIOSSLCertificateSource {
    @available(*, deprecated, message: "Use 'NIOSSLCertificate.fromPEMFile(_:)' to load the certificate(s) and use the '.certificate(NIOSSLCertificate)' case to provide them as a source")
    case file(String)
    case certificate(NIOSSLCertificate)
}

/// Places NIOSSL can obtain private keys from.
public enum NIOSSLPrivateKeySource {
    case file(String)
    case privateKey(NIOSSLPrivateKey)
}

/// Places NIOSSL can obtain a trust store from.
public enum NIOSSLTrustRoots {
    case file(String)
    case certificates([NIOSSLCertificate])
    case `default`
}

/// Formats NIOSSL supports for serializing keys and certificates.
public enum NIOSSLSerializationFormats {
    case pem
    case der
}

/// Certificate verification modes.
public enum CertificateVerification {
    /// All certificate verification disabled.
    case none

    /// Certificates will be validated against the trust store, but will not
    /// be checked to see if they are valid for the given hostname.
    case noHostnameVerification

    /// Certificates will be validated against the trust store and checked
    /// against the hostname of the service we are contacting.
    case fullVerification
}

/// Support for TLS renegotiation.
///
/// In general, renegotiation should not be enabled except in circumstances where it is absolutely necessary.
/// Renegotiation is only supported in TLS 1.2 and earlier, and generally does not work very well. NIOSSL will
/// disallow most uses of renegotiation: the only supported use-case is to perform post-connection authentication
/// *as a client*. There is no way to initiate a TLS renegotiation in NIOSSL.
public enum NIORenegotiationSupport {
    /// No support for TLS renegotiation. The default and recommended setting.
    case none

    /// Allow renegotiation exactly once. If you must use renegotiation, use this setting.
    case once

    /// Allow repeated renegotiation. To be avoided.
    case always
}

/// A secure default configuration of cipher suites for TLS 1.2 and earlier.
///
/// The goal of this cipher suite string is:
/// - Prefer cipher suites that offer Perfect Forward Secrecy (DHE/ECDHE)
/// - Prefer ECDH(E) to DH(E) for performance.
/// - Prefer any AEAD cipher suite over non-AEAD suites for better performance and security
/// - Prefer AES-GCM over ChaCha20 because hardware-accelerated AES is common
/// - Disable NULL authentication and encryption and any appearance of MD5
public let defaultCipherSuites = [
    "ECDH+AESGCM",
    "ECDH+CHACHA20",
    "DH+AESGCM",
    "DH+CHACHA20",
    "ECDH+AES256",
    "DH+AES256",
    "ECDH+AES128",
    "DH+AES",
    "RSA+AESGCM",
    "RSA+AES",
    "!aNULL",
    "!eNULL",
    "!MD5",
    ].joined(separator: ":")

/// Encodes a string to the wire format of an ALPN identifier. These MUST be ASCII, and so
/// this routine will crash the program if they aren't, as these are always user-supplied
/// strings.
internal func encodeALPNIdentifier(identifier: String) -> [UInt8] {
    var encodedIdentifier = [UInt8]()
    encodedIdentifier.append(UInt8(identifier.utf8.count))

    for codePoint in identifier.unicodeScalars {
        encodedIdentifier.append(contentsOf: Unicode.ASCII.encode(codePoint)!)
    }

    return encodedIdentifier
}

/// Decodes a string from the wire format of an ALPN identifier. These MUST be correctly
/// formatted ALPN identifiers, and so this routine will crash the program if they aren't.
internal func decodeALPNIdentifier(identifier: [UInt8]) -> String {
    return String(decoding: identifier[1..<identifier.count], as: Unicode.ASCII.self)
}

/// Manages configuration of TLS for SwiftNIO programs.
public struct TLSConfiguration {
    /// A default TLS configuration for client use.
    public static let clientDefault = TLSConfiguration.forClient()

    /// The minimum TLS version to allow in negotiation. Defaults to tlsv1.
    public var minimumTLSVersion: TLSVersion

    /// The maximum TLS version to allow in negotiation. If nil, there is no upper limit. Defaults to nil.
    public var maximumTLSVersion: TLSVersion?

    /// The pre-TLS1.3 cipher suites supported by this handler. This uses the OpenSSL cipher string format.
    /// TLS 1.3 cipher suites cannot be configured.
    public var cipherSuites: String

    /// Whether to verify remote certificates.
    public var certificateVerification: CertificateVerification

    /// The trust roots to use to validate certificates. This only needs to be provided if you intend to validate
    /// certificates.
    public var trustRoots: NIOSSLTrustRoots?

    /// The certificates to offer during negotiation. If not present, no certificates will be offered.
    public var certificateChain: [NIOSSLCertificateSource]

    /// The private key associated with the leaf certificate.
    public var privateKey: NIOSSLPrivateKeySource?

    /// The application protocols to use in the connection. Should be an ordered list of ASCII
    /// strings representing the ALPN identifiers of the protocols to negotiate. For clients,
    /// the protocols will be offered in the order given. For servers, the protocols will be matched
    /// against the client's offered protocols in order.
    public var applicationProtocols: [String] {
        get {
            return self.encodedApplicationProtocols.map(decodeALPNIdentifier)
        }
        set {
            self.encodedApplicationProtocols = newValue.map(encodeALPNIdentifier)
        }
    }

    internal var encodedApplicationProtocols: [[UInt8]]

    /// The amount of time to wait after initiating a shutdown before performing an unclean
    /// shutdown. Defaults to 5 seconds.
    public var shutdownTimeout: TimeAmount

    /// A callback that can be used to implement `SSLKEYLOGFILE` support.
    public var keyLogCallback: NIOSSLKeyLogCallback?

    /// Whether renegotiation is supported.
    public var renegotiationSupport: NIORenegotiationSupport

    private init(cipherSuites: String,
                 minimumTLSVersion: TLSVersion,
                 maximumTLSVersion: TLSVersion?,
                 certificateVerification: CertificateVerification,
                 trustRoots: NIOSSLTrustRoots,
                 certificateChain: [NIOSSLCertificateSource],
                 privateKey: NIOSSLPrivateKeySource?,
                 applicationProtocols: [String],
                 shutdownTimeout: TimeAmount,
                 keyLogCallback: NIOSSLKeyLogCallback?,
                 renegotiationSupport: NIORenegotiationSupport) {
        self.cipherSuites = cipherSuites
        self.minimumTLSVersion = minimumTLSVersion
        self.maximumTLSVersion = maximumTLSVersion
        self.certificateVerification = certificateVerification
        self.trustRoots = trustRoots
        self.certificateChain = certificateChain
        self.privateKey = privateKey
        self.encodedApplicationProtocols = []
        self.shutdownTimeout = shutdownTimeout
        self.renegotiationSupport = renegotiationSupport
        self.applicationProtocols = applicationProtocols
        self.keyLogCallback = keyLogCallback
    }

    /// Create a TLS configuration for use with server-side contexts.
    ///
    /// This provides sensible defaults while requiring that you provide any data that is necessary
    /// for server-side function. For client use, try `forClient` instead.
    public static func forServer(certificateChain: [NIOSSLCertificateSource],
                                 privateKey: NIOSSLPrivateKeySource,
                                 cipherSuites: String = defaultCipherSuites,
                                 minimumTLSVersion: TLSVersion = .tlsv1,
                                 maximumTLSVersion: TLSVersion? = nil,
                                 certificateVerification: CertificateVerification = .none,
                                 trustRoots: NIOSSLTrustRoots = .default,
                                 applicationProtocols: [String] = [],
                                 shutdownTimeout: TimeAmount = .seconds(5),
                                 keyLogCallback: NIOSSLKeyLogCallback? = nil) -> TLSConfiguration {
        return TLSConfiguration(cipherSuites: cipherSuites,
                                minimumTLSVersion: minimumTLSVersion,
                                maximumTLSVersion: maximumTLSVersion,
                                certificateVerification: certificateVerification,
                                trustRoots: trustRoots,
                                certificateChain: certificateChain,
                                privateKey: privateKey,
                                applicationProtocols: applicationProtocols,
                                shutdownTimeout: shutdownTimeout,
                                keyLogCallback: keyLogCallback,
                                renegotiationSupport: .none)  // Servers never support renegotiation: there's no point.
    }


    /// Creates a TLS configuration for use with client-side contexts.
    ///
    /// This provides sensible defaults, and can be used without customisation. For server-side
    /// contexts, you should use `forServer` instead.
    public static func forClient(cipherSuites: String = defaultCipherSuites,
                                 minimumTLSVersion: TLSVersion = .tlsv1,
                                 maximumTLSVersion: TLSVersion? = nil,
                                 certificateVerification: CertificateVerification = .fullVerification,
                                 trustRoots: NIOSSLTrustRoots = .default,
                                 certificateChain: [NIOSSLCertificateSource] = [],
                                 privateKey: NIOSSLPrivateKeySource? = nil,
                                 applicationProtocols: [String] = [],
                                 shutdownTimeout: TimeAmount = .seconds(5),
                                 keyLogCallback: NIOSSLKeyLogCallback? = nil) -> TLSConfiguration {
        return TLSConfiguration(cipherSuites: cipherSuites,
                                minimumTLSVersion: minimumTLSVersion,
                                maximumTLSVersion: maximumTLSVersion,
                                certificateVerification: certificateVerification,
                                trustRoots: trustRoots,
                                certificateChain: certificateChain,
                                privateKey: privateKey,
                                applicationProtocols: applicationProtocols,
                                shutdownTimeout: shutdownTimeout,
                                keyLogCallback: keyLogCallback,
                                renegotiationSupport: .none)  // Default value is here for backward-compatibility.
    }


    /// Creates a TLS configuration for use with client-side contexts.
    ///
    /// This provides sensible defaults, and can be used without customisation. For server-side
    /// contexts, you should use `forServer` instead.
    public static func forClient(cipherSuites: String = defaultCipherSuites,
                                 minimumTLSVersion: TLSVersion = .tlsv1,
                                 maximumTLSVersion: TLSVersion? = nil,
                                 certificateVerification: CertificateVerification = .fullVerification,
                                 trustRoots: NIOSSLTrustRoots = .default,
                                 certificateChain: [NIOSSLCertificateSource] = [],
                                 privateKey: NIOSSLPrivateKeySource? = nil,
                                 applicationProtocols: [String] = [],
                                 shutdownTimeout: TimeAmount = .seconds(5),
                                 keyLogCallback: NIOSSLKeyLogCallback? = nil,
                                 renegotiationSupport: NIORenegotiationSupport) -> TLSConfiguration {
        return TLSConfiguration(cipherSuites: cipherSuites,
                                minimumTLSVersion: minimumTLSVersion,
                                maximumTLSVersion: maximumTLSVersion,
                                certificateVerification: certificateVerification,
                                trustRoots: trustRoots,
                                certificateChain: certificateChain,
                                privateKey: privateKey,
                                applicationProtocols: applicationProtocols,
                                shutdownTimeout: shutdownTimeout,
                                keyLogCallback: keyLogCallback,
                                renegotiationSupport: renegotiationSupport)
    }
}
