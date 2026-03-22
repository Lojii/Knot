//
//  ThreadSafeCertPool.swift
//  TunnelServices
//
//  Thread-safe certificate pool for concurrent access from NIO EventLoops.
//

import Foundation
import NIOSSL

public class ThreadSafeCertPool {
    private var storage = [String: NIOSSLCertificate]()
    private let lock = NSLock()

    public init() {}

    public subscript(key: String) -> NIOSSLCertificate? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }
    }

    public func set(_ value: NIOSSLCertificate, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }
}
