//
//  QuicheConnection.swift
//  SwiftQuiche
//
//  Swift wrapper for Cloudflare's quiche QUIC + HTTP/3 C library.
//

import Foundation
import CQuiche

// MARK: - QUIC Config

public class QUICConfig {
    let raw: OpaquePointer

    public init(version: UInt32 = 0x00000001) {
        raw = quiche_config_new(version)
    }

    deinit { quiche_config_free(raw) }

    public func loadCertChain(fromPEM path: String) -> Bool {
        path.withCString { quiche_config_load_cert_chain_from_pem_file(raw, $0) == 0 }
    }

    public func loadPrivateKey(fromPEM path: String) -> Bool {
        path.withCString { quiche_config_load_priv_key_from_pem_file(raw, $0) == 0 }
    }

    public func verifyPeer(_ verify: Bool) {
        quiche_config_verify_peer(raw, verify)
    }

    public func setApplicationProtocols(_ protos: [String]) {
        var data = Data()
        for proto in protos {
            data.append(UInt8(proto.utf8.count))
            data.append(contentsOf: proto.utf8)
        }
        data.withUnsafeBytes {
            let _ = quiche_config_set_application_protos(raw, $0.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count)
        }
    }

    public func setMaxIdleTimeout(_ ms: UInt64) { quiche_config_set_max_idle_timeout(raw, ms) }
    public func setMaxRecvUDPPayloadSize(_ v: Int) { quiche_config_set_max_recv_udp_payload_size(raw, v) }
    public func setMaxSendUDPPayloadSize(_ v: Int) { quiche_config_set_max_send_udp_payload_size(raw, v) }
    public func setInitialMaxData(_ v: UInt64) { quiche_config_set_initial_max_data(raw, v) }
    public func setInitialMaxStreamDataBidiLocal(_ v: UInt64) { quiche_config_set_initial_max_stream_data_bidi_local(raw, v) }
    public func setInitialMaxStreamDataBidiRemote(_ v: UInt64) { quiche_config_set_initial_max_stream_data_bidi_remote(raw, v) }
    public func setInitialMaxStreamDataUni(_ v: UInt64) { quiche_config_set_initial_max_stream_data_uni(raw, v) }
    public func setInitialMaxStreamsBidi(_ v: UInt64) { quiche_config_set_initial_max_streams_bidi(raw, v) }
    public func setInitialMaxStreamsUni(_ v: UInt64) { quiche_config_set_initial_max_streams_uni(raw, v) }
    public func setDisableActiveMigration(_ v: Bool) { quiche_config_set_disable_active_migration(raw, v) }

    public func applyDefaults() {
        setMaxIdleTimeout(30_000)
        setMaxRecvUDPPayloadSize(1350)
        setMaxSendUDPPayloadSize(1350)
        setInitialMaxData(10_000_000)
        setInitialMaxStreamDataBidiLocal(1_000_000)
        setInitialMaxStreamDataBidiRemote(1_000_000)
        setInitialMaxStreamDataUni(1_000_000)
        setInitialMaxStreamsBidi(100)
        setInitialMaxStreamsUni(100)
        setDisableActiveMigration(true)
    }
}

// MARK: - QUIC Connection

public class QUICConnection {
    let raw: OpaquePointer
    private var sendBuf = [UInt8](repeating: 0, count: 65535)

    /// Server-side: accept a connection.
    public init?(scid: Data, odcid: Data?, localAddr: sockaddr_in, peerAddr: sockaddr_in, config: QUICConfig) {
        var local = localAddr
        var peer = peerAddr

        let conn: OpaquePointer? = scid.withUnsafeBytes { scidPtr in
            let scidBase = scidPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)

            if let odcid = odcid {
                return odcid.withUnsafeBytes { odcidPtr in
                    withUnsafePointer(to: &local) { localPtr in
                        withUnsafePointer(to: &peer) { peerPtr in
                            localPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { localSA in
                                peerPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { peerSA in
                                    quiche_accept(
                                        scidBase, scid.count,
                                        odcidPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), odcid.count,
                                        localSA, socklen_t(MemoryLayout<sockaddr_in>.size),
                                        peerSA, socklen_t(MemoryLayout<sockaddr_in>.size),
                                        config.raw
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                return withUnsafePointer(to: &local) { localPtr in
                    withUnsafePointer(to: &peer) { peerPtr in
                        localPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { localSA in
                            peerPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { peerSA in
                                quiche_accept(
                                    scidBase, scid.count,
                                    nil, 0,
                                    localSA, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    peerSA, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    config.raw
                                )
                            }
                        }
                    }
                }
            }
        }

        guard let c = conn else { return nil }
        raw = c
    }

    /// Client-side: connect to server.
    public init?(serverName: String, scid: Data, localAddr: sockaddr_in, peerAddr: sockaddr_in, config: QUICConfig) {
        var local = localAddr
        var peer = peerAddr

        let conn: OpaquePointer? = serverName.withCString { namePtr in
            scid.withUnsafeBytes { scidPtr in
                withUnsafePointer(to: &local) { localPtr in
                    withUnsafePointer(to: &peer) { peerPtr in
                        localPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { localSA in
                            peerPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { peerSA in
                                quiche_connect(
                                    namePtr,
                                    scidPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), scid.count,
                                    localSA, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    peerSA, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    config.raw
                                )
                            }
                        }
                    }
                }
            }
        }

        guard let c = conn else { return nil }
        raw = c
    }

    deinit { quiche_conn_free(raw) }

    // MARK: - Packet I/O

    public func recv(_ data: Data) -> Int {
        return recv(data, from: nil, to: nil)
    }

    public func recv(_ data: Data, from peerAddr: sockaddr_in?, to localAddr: sockaddr_in?) -> Int {
        var buf = [UInt8](data)
        if var peer = peerAddr, var local = localAddr {
            return withUnsafeMutablePointer(to: &peer) { peerPtr in
                withUnsafeMutablePointer(to: &local) { localPtr in
                    peerPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { peerSA in
                        localPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { localSA in
                            var info = quiche_recv_info(
                                from: peerSA, from_len: socklen_t(MemoryLayout<sockaddr_in>.size),
                                to: localSA, to_len: socklen_t(MemoryLayout<sockaddr_in>.size)
                            )
                            return Int(quiche_conn_recv(raw, &buf, buf.count, &info))
                        }
                    }
                }
            }
        } else {
            var info = quiche_recv_info(from: nil, from_len: 0, to: nil, to_len: 0)
            return Int(quiche_conn_recv(raw, &buf, buf.count, &info))
        }
    }

    public func send() -> Data? {
        var info = quiche_send_info()
        let written = quiche_conn_send(raw, &sendBuf, sendBuf.count, &info)
        guard written > 0 else { return nil }
        return Data(sendBuf[..<Int(written)])
    }

    // MARK: - Stream I/O

    public func streamRecv(streamId: UInt64, maxLength: Int = 65535) -> (Data, Bool)? {
        var buf = [UInt8](repeating: 0, count: maxLength)
        var fin: Bool = false
        var errorCode: UInt64 = 0
        let read = quiche_conn_stream_recv(raw, streamId, &buf, maxLength, &fin, &errorCode)
        guard read >= 0 else { return nil }
        return (Data(buf[..<Int(read)]), fin)
    }

    public func streamSend(streamId: UInt64, data: Data, fin: Bool) -> Int {
        var buf = [UInt8](data)
        var errorCode: UInt64 = 0
        return Int(quiche_conn_stream_send(raw, streamId, &buf, buf.count, fin, &errorCode))
    }

    // MARK: - State

    public var isEstablished: Bool { quiche_conn_is_established(raw) }
    public var isClosed: Bool { quiche_conn_is_closed(raw) }
    public var isTimedOut: Bool { quiche_conn_is_timed_out(raw) }
    public func onTimeout() { quiche_conn_on_timeout(raw) }
    public var timeoutAsNanos: UInt64 { quiche_conn_timeout_as_nanos(raw) }

    public var readableStreams: [UInt64] {
        guard let iter = quiche_conn_readable(raw) else { return [] }
        defer { quiche_stream_iter_free(iter) }
        var streams = [UInt64]()
        var id: UInt64 = 0
        while quiche_stream_iter_next(iter, &id) { streams.append(id) }
        return streams
    }
}

// MARK: - HTTP/3

public class HTTP3Config {
    let raw: OpaquePointer
    public init() { raw = quiche_h3_config_new() }
    deinit { quiche_h3_config_free(raw) }
}

public class HTTP3Connection {
    let raw: OpaquePointer

    public init?(quicConn: QUICConnection, config: HTTP3Config) {
        guard let h3 = quiche_h3_conn_new_with_transport(quicConn.raw, config.raw) else { return nil }
        raw = h3
    }

    deinit { quiche_h3_conn_free(raw) }

    public enum Event {
        case headers(streamId: UInt64, headers: [(String, String)])
        case data(streamId: UInt64)
        case finished(streamId: UInt64)
        case reset(streamId: UInt64)
        case goaway(id: UInt64)
        case done
    }

    /// Class-based accumulator for safely passing header storage through C callback void*.
    private class _HeaderAccumulator {
        var headers: [(String, String)] = []
    }

    public func poll(quicConn: QUICConnection) -> Event {
        var ev: OpaquePointer?
        let streamId = quiche_h3_conn_poll(raw, quicConn.raw, &ev)
        if streamId < 0 { return .done }
        guard let event = ev else { return .done }
        defer { quiche_h3_event_free(event) }

        let eventType = quiche_h3_event_type(event)
        switch eventType {
        case QUICHE_H3_EVENT_HEADERS:
            let accumulator = _HeaderAccumulator()
            let accPtr = Unmanaged.passUnretained(accumulator).toOpaque()
            quiche_h3_event_for_each_header(event, { name, nameLen, value, valueLen, argp in
                guard let argp = argp else { return 0 }
                let acc = Unmanaged<HTTP3Connection._HeaderAccumulator>.fromOpaque(argp).takeUnretainedValue()
                let n = String(bytes: UnsafeBufferPointer(start: name!, count: nameLen), encoding: .utf8) ?? ""
                let v = String(bytes: UnsafeBufferPointer(start: value!, count: valueLen), encoding: .utf8) ?? ""
                acc.headers.append((n, v))
                return 0
            }, accPtr)
            return .headers(streamId: UInt64(streamId), headers: accumulator.headers)
        case QUICHE_H3_EVENT_DATA:
            return .data(streamId: UInt64(streamId))
        case QUICHE_H3_EVENT_FINISHED:
            return .finished(streamId: UInt64(streamId))
        case QUICHE_H3_EVENT_RESET:
            return .reset(streamId: UInt64(streamId))
        case QUICHE_H3_EVENT_GOAWAY:
            return .goaway(id: UInt64(streamId))
        default:
            return .done
        }
    }

    public func recvBody(quicConn: QUICConnection, streamId: UInt64, maxLength: Int = 65535) -> Data? {
        var buf = [UInt8](repeating: 0, count: maxLength)
        let read = quiche_h3_recv_body(raw, quicConn.raw, streamId, &buf, maxLength)
        guard read > 0 else { return nil }
        return Data(buf[..<Int(read)])
    }

    public func sendRequest(quicConn: QUICConnection, headers: [(String, String)], fin: Bool) -> Int64 {
        let h3Headers = makeH3Headers(headers)
        var copy = h3Headers
        return copy.withUnsafeMutableBufferPointer { ptr in
            quiche_h3_send_request(raw, quicConn.raw, ptr.baseAddress!, headers.count, fin)
        }
    }

    public func sendResponse(quicConn: QUICConnection, streamId: UInt64, headers: [(String, String)], fin: Bool) -> Int {
        let h3Headers = makeH3Headers(headers)
        var copy = h3Headers
        return copy.withUnsafeMutableBufferPointer { ptr in
            Int(quiche_h3_send_response(raw, quicConn.raw, streamId, ptr.baseAddress!, headers.count, fin))
        }
    }

    public func sendBody(quicConn: QUICConnection, streamId: UInt64, data: Data, fin: Bool) -> Int {
        var buf = [UInt8](data)
        return Int(quiche_h3_send_body(raw, quicConn.raw, streamId, &buf, buf.count, fin))
    }

    // MARK: - Header Conversion

    /// Convert Swift string pairs to quiche_h3_header array.
    /// Uses UnsafeMutablePointer because quiche expects uint8_t* (not const).
    private func makeH3Headers(_ headers: [(String, String)]) -> [quiche_h3_header] {
        return headers.map { (name, value) in
            let nameBytes = Array(name.utf8)
            let valueBytes = Array(value.utf8)

            // These pointers need to stay valid during the send call.
            // quiche copies them internally, so withUnsafeBufferPointer is sufficient.
            let namePtr = UnsafeMutablePointer<UInt8>.allocate(capacity: nameBytes.count)
            namePtr.initialize(from: nameBytes, count: nameBytes.count)
            let valuePtr = UnsafeMutablePointer<UInt8>.allocate(capacity: valueBytes.count)
            valuePtr.initialize(from: valueBytes, count: valueBytes.count)

            return quiche_h3_header(
                name: namePtr,
                name_len: nameBytes.count,
                value: valuePtr,
                value_len: valueBytes.count
            )
        }
    }
}

// MARK: - Helpers

public func makeIPv4Addr(ip: String, port: UInt16) -> sockaddr_in {
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    inet_pton(AF_INET, ip, &addr.sin_addr)
    return addr
}
