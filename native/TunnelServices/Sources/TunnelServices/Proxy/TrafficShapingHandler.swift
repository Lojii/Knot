//
//  TrafficShapingHandler.swift
//  TunnelServices
//
//  Bandwidth throttling and weak network simulation.
//  Implements token bucket algorithm for rate limiting.
//
//  Netty reference: handler/traffic/ChannelTrafficShapingHandler.java,
//                   GlobalTrafficShapingHandler.java, TrafficCounter.java
//

import Foundation
import NIO

// MARK: - Network Profile

public struct NetworkProfile: Equatable {
    public let name: String
    public let downloadBytesPerSecond: Int   // 0 = unlimited
    public let uploadBytesPerSecond: Int     // 0 = unlimited
    public let latencyMs: Int               // Extra latency per request
    public let packetLossRate: Double        // 0.0 ~ 1.0

    public init(name: String, download: Int = 0, upload: Int = 0, latency: Int = 0, packetLoss: Double = 0) {
        self.name = name
        self.downloadBytesPerSecond = download
        self.uploadBytesPerSecond = upload
        self.latencyMs = latency
        self.packetLossRate = packetLoss
    }

    // Presets
    public static let unlimited = NetworkProfile(name: "No Limit")
    public static let wifiFast = NetworkProfile(name: "WiFi (Fast)", download: 30_000_000, upload: 15_000_000, latency: 5)
    public static let wifiSlow = NetworkProfile(name: "WiFi (Slow)", download: 1_000_000, upload: 500_000, latency: 50)
    public static let lte = NetworkProfile(name: "4G LTE", download: 12_000_000, upload: 5_000_000, latency: 50)
    public static let threeG = NetworkProfile(name: "3G", download: 384_000, upload: 128_000, latency: 200)
    public static let edge = NetworkProfile(name: "2G EDGE", download: 50_000, upload: 25_000, latency: 500)
    public static let veryBad = NetworkProfile(name: "Very Bad", download: 10_000, upload: 5_000, latency: 1000, packetLoss: 0.1)
    public static let lossy = NetworkProfile(name: "Lossy (5%)", download: 5_000_000, upload: 2_000_000, latency: 100, packetLoss: 0.05)

    public static let allPresets: [NetworkProfile] = [unlimited, wifiFast, wifiSlow, lte, threeG, edge, veryBad, lossy]
}

// MARK: - Traffic Shaping Handler

public final class TrafficShapingHandler: ChannelDuplexHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let profile: NetworkProfile
    private var downloadBucket: TokenBucket?
    private var uploadBucket: TokenBucket?

    public init(profile: NetworkProfile) {
        self.profile = profile
        if profile.downloadBytesPerSecond > 0 {
            downloadBucket = TokenBucket(bytesPerSecond: profile.downloadBytesPerSecond)
        }
        if profile.uploadBytesPerSecond > 0 {
            uploadBucket = TokenBucket(bytesPerSecond: profile.uploadBytesPerSecond)
        }
    }

    // MARK: - Inbound (download)

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let size = buffer.readableBytes

        // Packet loss simulation
        if profile.packetLossRate > 0 && Double.random(in: 0...1) < profile.packetLossRate {
            return  // Drop the packet
        }

        // Rate limiting
        if let bucket = downloadBucket {
            let delay = bucket.consume(size)
            if delay > 0 {
                let totalDelay = delay + Double(profile.latencyMs) / 1000.0
                context.eventLoop.scheduleTask(in: .milliseconds(Int64(totalDelay * 1000))) {
                    context.fireChannelRead(data)
                }
                return
            }
        }

        // Latency simulation
        if profile.latencyMs > 0 {
            context.eventLoop.scheduleTask(in: .milliseconds(Int64(profile.latencyMs))) {
                context.fireChannelRead(data)
            }
            return
        }

        context.fireChannelRead(data)
    }

    // MARK: - Outbound (upload)

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        let size = buffer.readableBytes

        // Packet loss
        if profile.packetLossRate > 0 && Double.random(in: 0...1) < profile.packetLossRate {
            promise?.succeed(())  // Silently drop
            return
        }

        // Rate limiting
        if let bucket = uploadBucket {
            let delay = bucket.consume(size)
            if delay > 0 {
                context.eventLoop.scheduleTask(in: .milliseconds(Int64(delay * 1000))) {
                    context.write(data, promise: promise)
                }
                return
            }
        }

        context.write(data, promise: promise)
    }
}

// MARK: - Token Bucket Algorithm

/// Classic token bucket for rate limiting.
/// Tokens are added at a constant rate. Each byte consumes one token.
/// If no tokens available, returns the delay needed to wait.
private class TokenBucket {
    private let rate: Double         // tokens (bytes) per second
    private let capacity: Double     // max burst size
    private var tokens: Double
    private var lastRefill: Double   // timestamp

    init(bytesPerSecond: Int) {
        self.rate = Double(bytesPerSecond)
        self.capacity = Double(bytesPerSecond)  // 1 second burst
        self.tokens = self.capacity
        self.lastRefill = CFAbsoluteTimeGetCurrent()
    }

    /// Consume tokens. Returns delay in seconds (0 = no delay needed).
    func consume(_ bytes: Int) -> Double {
        refill()
        let needed = Double(bytes)
        if tokens >= needed {
            tokens -= needed
            return 0
        }
        // Calculate wait time
        let deficit = needed - tokens
        tokens = 0
        return deficit / rate
    }

    private func refill() {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastRefill
        tokens = min(capacity, tokens + elapsed * rate)
        lastRefill = now
    }
}

// MARK: - Global Traffic Counter

/// Tracks global traffic statistics across all connections.
public class TrafficCounter {
    public static let shared = TrafficCounter()

    private let lock = NSLock()
    private var _totalUpload: Int64 = 0
    private var _totalDownload: Int64 = 0
    private var _activeConnections: Int = 0

    public var totalUpload: Int64 {
        lock.lock(); defer { lock.unlock() }; return _totalUpload
    }
    public var totalDownload: Int64 {
        lock.lock(); defer { lock.unlock() }; return _totalDownload
    }
    public var activeConnections: Int {
        lock.lock(); defer { lock.unlock() }; return _activeConnections
    }

    public func addUpload(_ bytes: Int) {
        lock.lock(); _totalUpload += Int64(bytes); lock.unlock()
    }
    public func addDownload(_ bytes: Int) {
        lock.lock(); _totalDownload += Int64(bytes); lock.unlock()
    }
    public func connectionOpened() {
        lock.lock(); _activeConnections += 1; lock.unlock()
    }
    public func connectionClosed() {
        lock.lock(); _activeConnections -= 1; lock.unlock()
    }
    public func reset() {
        lock.lock(); _totalUpload = 0; _totalDownload = 0; lock.unlock()
    }
}
