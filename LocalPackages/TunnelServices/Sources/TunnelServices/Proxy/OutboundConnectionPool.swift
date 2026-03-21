//
//  OutboundConnectionPool.swift
//  TunnelServices
//
//  Connection pool for reusing outbound TCP connections across client sessions.
//  Keyed by (host, port, isSSL). Thread-safe via NIOLock.
//

import Foundation
import NIO
import NIOConcurrencyHelpers

// MARK: - ConnectionPoolKey

/// Key for pooling outbound connections: (host, port, isSSL).
public struct ConnectionPoolKey: Hashable {
    public let host: String
    public let port: Int
    public let isSSL: Bool

    public init(host: String, port: Int, isSSL: Bool) {
        self.host = host
        self.port = port
        self.isSSL = isSSL
    }
}

// MARK: - PooledConnection

/// Wraps an idle NIO Channel with timestamps for eviction decisions.
struct PooledConnection {
    let channel: Channel
    /// When the TCP connection was originally established (not reset on reuse).
    let createdAt: NIODeadline
    /// When this connection was last returned to the pool.
    var lastUsedAt: NIODeadline

    init(channel: Channel, createdAt: NIODeadline? = nil, now: NIODeadline = .now()) {
        self.channel = channel
        self.createdAt = createdAt ?? now
        self.lastUsedAt = now
    }
}

// MARK: - OutboundConnectionPool

/// A bounded, thread-safe pool of idle outbound NIO Channels.
///
/// - Max 6 connections per key
/// - Max 32 total connections
/// - Idle eviction after 30s
/// - TTL eviction after 5min
/// - Periodic eviction every 10s
public final class OutboundConnectionPool {

    // MARK: - Configuration

    public static let maxConnectionsPerKey = 6
    public static let maxTotalConnections = 32
    public static let idleTimeout: TimeAmount = .seconds(30)
    public static let maxTTL: TimeAmount = .seconds(300)  // 5 minutes
    public static let evictionInterval: TimeAmount = .seconds(10)

    // MARK: - State

    private let lock = NIOLock()
    private var pool: [ConnectionPoolKey: [PooledConnection]] = [:]
    private var totalCount: Int = 0
    private var evictionTask: RepeatedTask?
    private var closed = false

    public init() {}

    // MARK: - Checkout

    /// Result of a successful checkout: the channel and its original creation time.
    public struct CheckoutResult {
        public let channel: Channel
        /// Original TCP connection creation time — pass back to checkin to preserve TTL.
        public let createdAt: NIODeadline
    }

    /// Retrieve an idle connection for the given key, or nil if none available.
    /// Uses LIFO order (most recently used first). Skips closed channels.
    public func checkout(key: ConnectionPoolKey) -> CheckoutResult? {
        lock.lock()
        defer { lock.unlock() }

        guard !closed else { return nil }
        guard var entries = pool[key], !entries.isEmpty else { return nil }

        // LIFO: pop from end, skip closed
        while let entry = entries.popLast() {
            totalCount -= 1
            if entry.channel.isActive {
                if entries.isEmpty {
                    pool.removeValue(forKey: key)
                } else {
                    pool[key] = entries
                }
                return CheckoutResult(channel: entry.channel, createdAt: entry.createdAt)
            }
            // Channel was closed while idle; discard and try next
        }

        // All entries were closed
        pool.removeValue(forKey: key)
        return nil
    }

    // MARK: - Checkin

    /// Return an idle connection to the pool. If the pool is full or the channel
    /// is inactive, the channel is closed instead.
    /// Pass `createdAt` from `CheckoutResult` to preserve the original TCP creation time for TTL.
    public func checkin(key: ConnectionPoolKey, channel: Channel, createdAt: NIODeadline? = nil) {
        lock.lock()

        guard !closed else {
            lock.unlock()
            channel.close(mode: .all, promise: nil)
            return
        }

        guard channel.isActive else {
            lock.unlock()
            return
        }

        var entries = pool[key] ?? []

        // Enforce per-key limit
        if entries.count >= OutboundConnectionPool.maxConnectionsPerKey {
            lock.unlock()
            channel.close(mode: .all, promise: nil)
            return
        }

        // Enforce total limit
        if totalCount >= OutboundConnectionPool.maxTotalConnections {
            lock.unlock()
            channel.close(mode: .all, promise: nil)
            return
        }

        let entry = PooledConnection(channel: channel, createdAt: createdAt)
        entries.append(entry)
        pool[key] = entries
        totalCount += 1
        lock.unlock()
    }

    // MARK: - Eviction

    /// Remove connections that are idle > 30s or older than 5min TTL.
    public func evictExpired() {
        lock.lock()

        let now = NIODeadline.now()
        var toClose = [Channel]()

        for (key, entries) in pool {
            var kept = [PooledConnection]()
            for entry in entries {
                let idleAge = now - entry.lastUsedAt
                let totalAge = now - entry.createdAt
                if !entry.channel.isActive
                    || idleAge >= OutboundConnectionPool.idleTimeout
                    || totalAge >= OutboundConnectionPool.maxTTL {
                    toClose.append(entry.channel)
                    totalCount -= 1
                } else {
                    kept.append(entry)
                }
            }
            if kept.isEmpty {
                pool.removeValue(forKey: key)
            } else {
                pool[key] = kept
            }
        }

        lock.unlock()

        // Close outside of lock
        for channel in toClose {
            channel.close(mode: .all, promise: nil)
        }
    }

    /// Start periodic eviction on the given event loop.
    public func startEviction(on eventLoop: EventLoop) {
        lock.lock()
        guard evictionTask == nil, !closed else {
            lock.unlock()
            return
        }
        lock.unlock()

        let task = eventLoop.scheduleRepeatedTask(
            initialDelay: OutboundConnectionPool.evictionInterval,
            delay: OutboundConnectionPool.evictionInterval
        ) { [weak self] _ in
            self?.evictExpired()
        }

        // Re-check closed state to avoid TOCTOU race: closeAll() may have run
        // between the first unlock and here, setting closed=true and cancelling
        // evictionTask. Without this check, we'd store a new task that never
        // gets cancelled.
        lock.lock()
        if closed {
            lock.unlock()
            task.cancel()
            return
        }
        self.evictionTask = task
        lock.unlock()
    }

    // MARK: - Shutdown

    /// Close all pooled connections and stop eviction.
    public func closeAll() {
        lock.lock()
        closed = true
        evictionTask?.cancel()
        evictionTask = nil

        var toClose = [Channel]()
        for (_, entries) in pool {
            for entry in entries {
                toClose.append(entry.channel)
            }
        }
        pool.removeAll()
        totalCount = 0
        lock.unlock()

        for channel in toClose {
            channel.close(mode: .all, promise: nil)
        }
    }

    // MARK: - Diagnostics (for testing)

    /// Returns the current number of pooled connections (for testing).
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalCount
    }

    /// Returns the number of pooled connections for a specific key (for testing).
    public func count(for key: ConnectionPoolKey) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return pool[key]?.count ?? 0
    }

    /// Returns per-key connection counts for dashboard metrics.
    public func perKeyBreakdown() -> [(key: String, count: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return pool.map { (key, entries) in
            ("\(key.host):\(key.port):\(key.isSSL ? "ssl" : "tcp")", entries.count)
        }
    }
}
