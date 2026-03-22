//
//  IPFilterHandler.swift
//  TunnelServices
//
//  IP-based access control for the proxy server.
//  Filter connections by IP address or CIDR subnet.
//
//  Netty reference: handler/ipfilter/RuleBasedIpFilter.java,
//                   IpSubnetFilter.java, UniqueIpFilter.java
//

import Foundation
import NIO

// MARK: - IP Filter Rule

public struct IPFilterRule {
    public enum Action { case accept, reject }

    public let cidr: String    // "192.168.1.0/24" or "10.0.0.5"
    public let action: Action

    public init(cidr: String, action: Action) {
        self.cidr = cidr
        self.action = action
    }

    /// Check if the given IP matches this rule.
    public func matches(_ ip: String) -> Bool {
        if !cidr.contains("/") {
            return ip == cidr  // Exact match
        }
        // CIDR subnet matching
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let maskBits = Int(parts[1]),
              maskBits >= 0 && maskBits <= 32 else { return false }

        let subnetIP = String(parts[0])
        guard let subnetAddr = ipToUInt32(subnetIP),
              let testAddr = ipToUInt32(ip) else { return false }

        let mask: UInt32 = maskBits == 0 ? 0 : ~((1 << (32 - maskBits)) - 1)
        return (subnetAddr & mask) == (testAddr & mask)
    }

    private func ipToUInt32(_ ip: String) -> UInt32? {
        let octets = ip.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }
        return UInt32(octets[0]) << 24 | UInt32(octets[1]) << 16 | UInt32(octets[2]) << 8 | UInt32(octets[3])
    }
}

// MARK: - IP Filter Handler

public final class IPFilterHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    public enum Mode {
        case whitelist  // Only allow matched IPs
        case blacklist  // Reject matched IPs
    }

    private let rules: [IPFilterRule]
    private let mode: Mode

    public init(rules: [IPFilterRule], mode: Mode = .blacklist) {
        self.rules = rules
        self.mode = mode
    }

    public func channelActive(context: ChannelHandlerContext) {
        guard let remoteAddress = context.channel.remoteAddress,
              let ip = extractIP(from: remoteAddress) else {
            context.fireChannelActive()
            return
        }

        let allowed = evaluate(ip)
        if !allowed {
            AxLogger.log("IPFilter: rejected connection from \(ip)", level: .Info)
            context.close(promise: nil)
            return
        }

        context.fireChannelActive()
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    private func evaluate(_ ip: String) -> Bool {
        switch mode {
        case .whitelist:
            // Must match at least one accept rule
            return rules.contains { $0.action == .accept && $0.matches(ip) }
        case .blacklist:
            // Must NOT match any reject rule
            return !rules.contains { $0.action == .reject && $0.matches(ip) }
        }
    }

    private func extractIP(from address: SocketAddress) -> String? {
        switch address {
        case .v4(let addr): return addr.host
        case .v6(let addr): return addr.host
        default: return nil
        }
    }
}

// MARK: - Unique IP Filter

/// Allows only one connection per IP address.
/// Netty reference: UniqueIpFilter.java
public final class UniqueIPFilter: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer

    private static var connectedIPs = Set<String>()
    private static let lock = NSLock()
    private var myIP: String?

    public func channelActive(context: ChannelHandlerContext) {
        guard let ip = context.channel.remoteAddress?.ipAddress else {
            context.fireChannelActive()
            return
        }

        UniqueIPFilter.lock.lock()
        let isNew = UniqueIPFilter.connectedIPs.insert(ip).inserted
        UniqueIPFilter.lock.unlock()

        if isNew {
            myIP = ip
            context.fireChannelActive()
        } else {
            AxLogger.log("UniqueIPFilter: duplicate connection from \(ip)", level: .Info)
            context.close(promise: nil)
        }
    }

    public func channelInactive(context: ChannelHandlerContext) {
        if let ip = myIP {
            UniqueIPFilter.lock.lock()
            UniqueIPFilter.connectedIPs.remove(ip)
            UniqueIPFilter.lock.unlock()
        }
        context.fireChannelInactive()
    }
}
