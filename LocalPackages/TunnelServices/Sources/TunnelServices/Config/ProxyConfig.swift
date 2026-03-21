//
//  ProxyConfig.swift
//  TunnelServices
//
//  Centralized configuration for proxy service, network, and file paths.
//  All previously hardcoded values are managed here.
//

import Foundation

public enum ProxyConfig {

    // MARK: - App Identifiers

    public static let appGroupIdentifier = "group.Lojii.NIO1901"
    public static let extensionBundleIdentifier = "Lojii.NIO1901.PacketTunnel"

    // MARK: - Local Proxy Server

    public enum LocalProxy {
        public static let host = "127.0.0.1"
        public static let port: Int = 8034
        public static var endpoint: String { "\(host):\(port)" }
    }

    // MARK: - WiFi Proxy (default)

    public enum WiFiProxy {
        public static let defaultPort: Int = 8034
    }

    // MARK: - VPN Tunnel

    public enum VPN {
        public static let tunnelAddress = "127.0.0.1"
        public static let ipv4Address = "192.169.89.1"
        public static let ipv6Address = "fd00::1"
        public static let subnetMask = "255.255.255.0"
        public static let mtu: NSNumber = 1500
        public static let dnsServers = ["8.8.8.8", "8.8.4.4"]

        /// Networks excluded from tunnel (to prevent routing loops)
        public static let excludedIPv4Routes = [
            ("127.0.0.0", "255.0.0.0"),       // localhost
            ("192.168.0.0", "255.255.0.0"),    // private
            ("10.0.0.0", "255.0.0.0"),         // private
        ]
    }

    // MARK: - Packet Capture

    public enum PacketCapture {
        public static let enableTCPCapture = true
        public static let enableUDPCapture = true
        public static let enableICMPCapture = true
        public static let enablePCAPRecording = false
        public static let maxPCAPFileSize = 50 * 1024 * 1024  // 50MB
    }

    // MARK: - HTTP/3 (QUIC MITM)

    public enum HTTP3 {
        /// Enable HTTP/3 MITM interception.
        /// When false, QUIC packets are dropped to force HTTP/2 fallback.
        public static var enabled = false

        /// QUIC backend engine selection.
        public enum Backend: String {
            case quiche = "quiche"    // Cloudflare quiche (Rust, 43MB, poll-based)
            case lsquic = "lsquic"   // LiteSpeed lsquic (C, 31MB, callback-based)
        }

        /// Which QUIC engine to use. Can be switched at runtime before enabling.
        public static var backend: Backend = .quiche

        /// Maximum concurrent QUIC MITM sessions (memory management).
        public static let maxSessions = 20

        /// QUIC idle timeout in milliseconds.
        public static let idleTimeoutMs: UInt64 = 30_000

        /// UDP port for QUIC transparent proxy mode.
        public static var udpPort: Int = 8443
    }

    // MARK: - SSL/TLS

    public enum SSL {
        public static let handshakeTimeout: Int64 = 10  // seconds
        public static let connectTimeout: Int64 = 10    // seconds
        public static let checkHost = "www.localhost.com"
        public static let checkPort: Int = 4433
    }

    // MARK: - HTTP Server

    public enum HTTPServer {
        public static let defaultHost = "::1"
        public static let defaultPort: Int = 80
    }

    // MARK: - IPC (Inter-Process Communication)

    public enum IPC {
        public static let udpHost = "127.0.0.1"
        public static let udpPort: UInt16 = 60001
    }

    // MARK: - Certificate Files

    public enum CertFiles {
        public static let caCert = "cacert.pem"
        public static let caCertDER = "cacert.der"
        public static let caKey = "cakey.pem"
        public static let rsaKey = "rsakey.pem"
        public static let blackList = "DefaultBlackLisk.conf"
    }

    // MARK: - Certificate Subject (for dynamic cert generation)

    public enum CertSubject {
        public static let country = "SE"
        public static let organization = "Company"
    }

    // MARK: - Connection (Keep-Alive / Pipelining)

    public enum Connection {
        /// Idle timeout for keep-alive connections (seconds).
        public static let keepAliveIdleTimeout: Int64 = 30
        /// Maximum lifetime for a single connection (seconds).
        public static let maxConnectionLifetime: Int64 = 300
        /// Maximum queued pipelined requests per connection.
        public static let maxPendingRequests: Int = 16
    }

    // MARK: - Database

    public enum Database {
        public static let fileName = "nio.db"
        public static let sessionTableName = "Session"
    }

    // MARK: - File Storage

    public enum Storage {
        public static let taskFolder = "Task"
        public static let certFolder = "Cert"
        public static let tunnelLogFolder = "Tunnel"
        public static let httpRootFolder = "Root"
        public static let wormholeDirectory = "wormhole"
        public static let indexHTML = "index.html"
    }
}
