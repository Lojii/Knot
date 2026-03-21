//
//  TestProxyLauncher.swift
//  TunnelServicesTests
//
//  Starts a real ProxyServer with database, CA certificates, and provides
//  query APIs for integration test assertions.
//

import Foundation
import NIO
import NIOSSL
import X509
import _CryptoExtras
@testable import TunnelServices

final class TestProxyLauncher {

    // MARK: - Configuration

    // sslEnabled removed — MITM decision is now based on isCACertTrusted (set from withCA)
    let withCA: Bool

    // MARK: - Exposed State for Assertions

    /// The test CA certificate (for configuring client trust).
    private(set) var caCertificate: NIOSSLCertificate?

    /// The test CA certificate in swift-certificates form.
    private(set) var x509CACert: Certificate?

    /// The RSA signing key used for dynamic cert generation.
    private(set) var rsaSigningKey: _RSA.Signing.PrivateKey?

    /// File folder path for this test task's artifacts.
    var taskFileFolder: String { task?.fileFolder ?? tempDir }

    /// The task ID (set after start()).
    var taskId: Int64 { task?.id ?? 0 }

    /// The outbound connection pool from the running task.
    var connectionPool: OutboundConnectionPool? { task?.connectionPool }

    /// The port the proxy is actually listening on (set after start()).
    private(set) var boundPort: Int = 0

    // MARK: - Internal State

    private var proxyServer: ProxyServer?
    private var task: CaptureTask?
    private let tempDir: String
    private var started = false

    // MARK: - Init

    /// Creates a TestProxyLauncher with a fresh temp directory.
    ///
    /// - Parameters:
    ///   - sslEnabled: Ignored (kept for call-site compatibility). MITM is controlled by withCA.
    ///   - withCA: Whether to generate a test CA certificate. When true, isCACertTrusted=true → MITM.
    init(sslEnabled: Bool = true, withCA: Bool = true) throws {
        self.withCA = withCA

        // Create a unique temp directory for all test artifacts
        let base = NSTemporaryDirectory()
        let unique = "TestProxy_\(ProcessInfo.processInfo.globallyUniqueString)"
        let dir = (base as NSString).appendingPathComponent(unique)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        self.tempDir = dir

        // Point MitmService.storeFolder at our temp dir so CaptureTask.createFileFolder() works
        MitmService.storeFolder = dir.hasSuffix("/") ? dir : "\(dir)/"
    }

    // MARK: - Lifecycle

    /// Start the proxy server and return the bound port.
    ///
    /// This method:
    /// 1. Generates test CA certificates (if withCA is true)
    /// 2. Constructs a CaptureTask manually (bypassing singletons)
    /// 3. Registers the task in the shared DatabaseManager's catalog
    /// 4. Starts ProxyServer and waits for the port to be bound
    ///
    /// - Returns: The TCP port the proxy is listening on.
    @discardableResult
    func start() throws -> Int {
        guard !started else { return boundPort }

        // Step 1: Generate test CA certificates
        var certManager: CertManager
        if withCA {
            let (caCert, caKey, rsaKey) = try CertGenerator.generateCA()

            let nioCACert = try CertGenerator.toNIOSSL(caCert)
            let caKeyPEM = caKey.pemRepresentation
            let rsaKeyPEM = rsaKey.pemRepresentation
            let nioCAKey = try NIOSSLPrivateKey(bytes: Array(caKeyPEM.utf8), format: .pem)
            let nioRSAKey = try NIOSSLPrivateKey(bytes: Array(rsaKeyPEM.utf8), format: .pem)

            certManager = CertManager(
                cacert: nioCACert,
                cakey: nioCAKey,
                rsakey: nioRSAKey,
                x509CACert: caCert,
                rsaSigningKey: rsaKey,
                caSigningKey: caKey
            )

            self.caCertificate = nioCACert
            self.x509CACert = caCert
            self.rsaSigningKey = rsaKey
        } else {
            certManager = CertManager(
                cacert: nil,
                cakey: nil,
                rsakey: nil,
                x509CACert: nil,
                rsaSigningKey: nil
            )
        }

        // Step 2: Construct CaptureTask manually (bypass newTask() which uses singletons)
        let task = CaptureTask()
        task.id = 0  // Will be set by save()
        task.localIP = "127.0.0.1"
        task.localPort = 0  // OS assigns an ephemeral port
        task.localEnable = 1
        task.wifiEnable = 0
        task.isCACertTrusted = withCA
        task.ruleEngine = RuleEngine(config: "")
        task.certManager = certManager
        task.creatTime = Date().timeIntervalSince1970
        let creatTimeStr = "\(task.creatTime!)".components(separatedBy: ".")
        task.fileFolder = "test_\(creatTimeStr.first ?? "0")\(creatTimeStr.last ?? "0")"
        task.startTime = Date().timeIntervalSince1970

        // Register in the shared catalog so SessionRecorder can find it
        // The shared DatabaseManager falls back to in-memory when app group is unavailable
        let catalogDB = DatabaseManager.shared.catalogDB
        let rowId = try CatalogDAO.insertFullTask(db: catalogDB, task: task)
        task.id = rowId
        self.task = task

        // Step 3: Ensure the shared DatabaseManager can open the task databases
        // (SessionRecorder uses DatabaseManager.shared.openTask())
        let _ = try DatabaseManager.shared.openTask(task.id)

        // Step 4: Start ProxyServer
        let server = ProxyServer(masterThreads: 1, workerThreads: 2)
        self.proxyServer = server

        let sem = DispatchSemaphore(value: 0)
        var startError: Error?

        server.start(task: task) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                startError = error
            }
            sem.signal()
        }

        sem.wait()

        if let error = startError {
            throw error
        }

        // Read the bound port from the channel
        guard let port = server.localBoundPort else {
            throw TestProxyError.portNotAvailable
        }
        self.boundPort = port
        self.started = true

        return port
    }

    /// Stop the proxy server and clean up all resources.
    func stop() {
        guard started else { return }
        started = false

        // Stop proxy server (closes channels and shuts down event loop groups)
        let stopSem = DispatchSemaphore(value: 0)
        proxyServer?.stop {
            stopSem.signal()
        }
        stopSem.wait()
        proxyServer = nil

        // Close task databases
        if let taskId = task?.id {
            DatabaseManager.shared.closeTask(taskId)
        }

        // Clean up connection pool
        task?.connectionPool.closeAll()

        task = nil

        // Remove temp directory
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    // MARK: - Query APIs

    /// Query all flow records for this test task.
    func queryFlows() throws -> [FlowRecord] {
        guard let taskId = task?.id, taskId > 0 else { return [] }
        let group = try DatabaseManager.shared.openTask(taskId)
        defer { DatabaseManager.shared.closeTask(taskId) }
        return try FlowDAO.query(db: group.proto, offset: 0, limit: 10000)
    }

    /// Find the first flow whose host contains the given substring.
    func findFlow(host: String) throws -> FlowRecord? {
        let flows = try queryFlows()
        return flows.first { $0.host.contains(host) }
    }

    /// Find a flow by its flow ID.
    func findFlow(flowId: String) throws -> FlowRecord? {
        guard let taskId = task?.id, taskId > 0 else { return nil }
        let group = try DatabaseManager.shared.openTask(taskId)
        defer { DatabaseManager.shared.closeTask(taskId) }
        return try FlowDAO.find(db: group.proto, flowId: flowId)
    }

    /// Query all TCP connection records for this test task.
    func queryConnections() throws -> [TcpConnectionRecord] {
        guard let taskId = task?.id, taskId > 0 else { return [] }
        let group = try DatabaseManager.shared.openTask(taskId)
        defer { DatabaseManager.shared.closeTask(taskId) }

        // TcpConnectionDAO doesn't have a query-all method, so use raw SQL
        var results: [TcpConnectionRecord] = []
        let stmt = try group.connection.prepare("SELECT * FROM tcp_connection ORDER BY started_at DESC")
        for row in stmt {
            let record = TcpConnectionRecord(
                flowId: row[1] as? String ?? "",
                srcIp: row[2] as? String ?? "",
                srcPort: Int(row[3] as? Int64 ?? 0),
                dstIp: row[4] as? String ?? "",
                dstPort: Int(row[5] as? Int64 ?? 0),
                startedAt: row[7] as? Double ?? 0,
                state: row[6] as? String ?? "open",
                establishedAt: row[8] as? Double,
                closedAt: row[9] as? Double,
                closeReason: row[10] as? String ?? "",
                tlsVersion: row[11] as? String ?? "",
                tlsCipher: row[12] as? String ?? "",
                tlsSni: row[13] as? String ?? "",
                serverCert: row[14] as? String ?? "",
                packetsIn: row[15] as? Int64 ?? 0,
                packetsOut: row[16] as? Int64 ?? 0,
                bytesIn: row[17] as? Int64 ?? 0,
                bytesOut: row[18] as? Int64 ?? 0
            )
            results.append(record)
        }
        return results
    }

    /// Find a TCP connection record by flow ID.
    func findConnection(flowId: String) throws -> TcpConnectionRecord? {
        guard let taskId = task?.id, taskId > 0 else { return nil }
        let group = try DatabaseManager.shared.openTask(taskId)
        defer { DatabaseManager.shared.closeTask(taskId) }
        return try TcpConnectionDAO.find(db: group.connection, flowId: flowId)
    }
}

// MARK: - Errors

enum TestProxyError: Error, CustomStringConvertible {
    case portNotAvailable
    case notStarted

    var description: String {
        switch self {
        case .portNotAvailable:
            return "ProxyServer started but bound port is not available"
        case .notStarted:
            return "TestProxyLauncher has not been started"
        }
    }
}
