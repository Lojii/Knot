//
//  QUICMITMTestHarness.swift
//  TunnelServicesTests
//
//  Routes QUIC packets through QUICMITMManager:
//    client → MITM (processOutbound) → server
//    server → MITM (processInbound) → client
//

import Foundation
import XCTest
@testable import TunnelServices

#if canImport(SwiftQuiche)
import SwiftQuiche

class QUICMITMTestHarness {

    let client: TestQUICClient
    let server: TestQUICServer
    let manager: QUICMITMManager

    let serverIP = "1.2.3.4"
    let serverPort: UInt16 = 443

    private let tempDir: String

    var sessionCount: Int { manager.activeSessions }

    init(
        client: TestQUICClient,
        server: TestQUICServer,
        certPath: String,
        keyPath: String,
        tempDir: String
    ) throws {
        self.client = client
        self.server = server
        self.tempDir = tempDir

        let task = CaptureTask()
        task.id = 0
        task.localIP = "127.0.0.1"
        task.localPort = 0
        task.localEnable = 1
        task.sslEnable = 1
        task.ruleEngine = RuleEngine(config: "")
        task.fileFolder = tempDir

        self.manager = QUICMITMManager(task: task, certPath: certPath, keyPath: keyPath)
    }

    // MARK: - Core Packet Pumping

    /// Feed a batch of client packets through MITM → server → MITM → client,
    /// iterating until no more packets are generated.
    /// Returns any new client outbound packets that were generated but not yet fed to the MITM.
    private func pumpOnce(_ clientPackets: [Data]) -> [Data] {
        var pendingClientPkts = clientPackets

        for _ in 0..<100 { // convergence limit
            if pendingClientPkts.isEmpty { break }

            // Client → MITM (processOutbound)
            var toApp = [Data]()
            var forServer = [Data]()
            for pkt in pendingClientPkts {
                let result = manager.processOutbound(pkt, dstIP: serverIP, dstPort: serverPort)
                toApp.append(contentsOf: result.toApp)
                for (data, _, _) in result.toServer {
                    forServer.append(data)
                }
            }
            pendingClientPkts.removeAll()

            // Server: receive packets and collect responses
            var serverResponses = [Data]()
            for pkt in forServer {
                serverResponses.append(contentsOf: server.receive(pkt))
            }
            serverResponses.append(contentsOf: server.pendingOutbound())

            // Server responses → MITM (processInbound), iteratively
            var pendingForServer = [Data]()
            for pkt in serverResponses {
                let result = manager.processInbound(pkt, srcIP: serverIP, srcPort: serverPort)
                toApp.append(contentsOf: result.toApp)
                for (data, _, _) in result.toServer {
                    pendingForServer.append(data)
                }
            }

            // Continue pumping MITM ↔ server until quiescent
            while !pendingForServer.isEmpty {
                var srvResp = [Data]()
                for pkt in pendingForServer {
                    srvResp.append(contentsOf: server.receive(pkt))
                }
                srvResp.append(contentsOf: server.pendingOutbound())
                pendingForServer.removeAll()
                if srvResp.isEmpty { break }
                for pkt in srvResp {
                    let result = manager.processInbound(pkt, srcIP: serverIP, srcPort: serverPort)
                    toApp.append(contentsOf: result.toApp)
                    for (data, _, _) in result.toServer {
                        pendingForServer.append(data)
                    }
                }
            }

            // Deliver toApp to client; capture any packets the client generates in response
            if !toApp.isEmpty {
                pendingClientPkts = client.receive(toApp)
            }
        }

        // Return any remaining client packets that weren't pumped
        return pendingClientPkts
    }

    /// Run one full exchange cycle. Returns true if any activity occurred.
    @discardableResult
    func runRoundTrip() -> Bool {
        let clientPkts = client.drainOutbound()
        if clientPkts.isEmpty {
            // Check if server has any pending outbound
            let srvOut = server.pendingOutbound()
            if srvOut.isEmpty { return false }

            var toApp = [Data]()
            var pendingForServer = [Data]()
            for pkt in srvOut {
                let result = manager.processInbound(pkt, srcIP: serverIP, srcPort: serverPort)
                toApp.append(contentsOf: result.toApp)
                for (data, _, _) in result.toServer {
                    pendingForServer.append(data)
                }
            }
            while !pendingForServer.isEmpty {
                var srvResp = [Data]()
                for pkt in pendingForServer {
                    srvResp.append(contentsOf: server.receive(pkt))
                }
                srvResp.append(contentsOf: server.pendingOutbound())
                pendingForServer.removeAll()
                if srvResp.isEmpty { break }
                for pkt in srvResp {
                    let result = manager.processInbound(pkt, srcIP: serverIP, srcPort: serverPort)
                    toApp.append(contentsOf: result.toApp)
                    for (data, _, _) in result.toServer {
                        pendingForServer.append(data)
                    }
                }
            }
            if !toApp.isEmpty {
                let morePkts = client.receive(toApp)
                // If client generated more packets, pump them
                if !morePkts.isEmpty {
                    let _ = pumpOnce(morePkts)
                }
                return true
            }
            return false
        }

        let remaining = pumpOnce(clientPkts)
        // Drain any final packets
        if !remaining.isEmpty {
            let _ = pumpOnce(remaining)
        }
        return true
    }

    /// Convenience: pump specific client packets and iterate until quiescent.
    @discardableResult
    func pumpClientPackets(_ packets: [Data]) -> Bool {
        let remaining = pumpOnce(packets)
        if !remaining.isEmpty {
            let _ = pumpOnce(remaining)
        }
        // Extra rounds for convergence
        for _ in 0..<10 {
            let progress = runRoundTrip()
            if !progress { break }
        }
        return true
    }

    /// Run round-trips until the client's QUIC connection is established.
    func runUntilEstablished(timeout: TimeInterval = 10.0) throws {
        let initialPackets = client.startConnection()
        pumpClientPackets(initialPackets)

        let deadline = Date().addingTimeInterval(timeout)
        while !client.isEstablished && Date() < deadline {
            let progress = runRoundTrip()
            if !progress {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        guard client.isEstablished else {
            throw NSError(
                domain: "QUICMITMTestHarness",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "QUIC handshake through MITM did not complete within \(timeout)s"]
            )
        }

        // Extra settle
        for _ in 0..<20 {
            let progress = runRoundTrip()
            if !progress { break }
        }
    }

    /// Run round-trips until the client has at least one completed response.
    func runUntilResponse(timeout: TimeInterval = 10.0) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            runRoundTrip()
            let responses = client.pollResponses()
            if !responses.isEmpty {
                return
            }
            Thread.sleep(forTimeInterval: 0.005)
        }

        throw NSError(
            domain: "QUICMITMTestHarness",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "No H3 response received through MITM within \(timeout)s"]
        )
    }

    /// Run round-trips until the client has accumulated at least `count` responses.
    func runUntilResponses(count: Int, timeout: TimeInterval = 10.0) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var totalResponses = 0
        while Date() < deadline {
            runRoundTrip()
            let responses = client.pollResponses()
            totalResponses += responses.count
            if totalResponses >= count {
                return
            }
            Thread.sleep(forTimeInterval: 0.005)
        }

        throw NSError(
            domain: "QUICMITMTestHarness",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Expected \(count) responses but got \(totalResponses) within \(timeout)s"]
        )
    }

    func shutdown() {
        manager.shutdown()
    }
}

#endif
