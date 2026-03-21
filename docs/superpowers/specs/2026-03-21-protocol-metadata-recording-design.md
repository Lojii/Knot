# Protocol Metadata Recording Design

**Goal:** Record detailed protocol feature usage, connection reuse status, push promise forwarding state, and full TLS certificate chains for every captured flow — supporting UI display, debugging, and aggregate statistical queries.

**Approach:** Add 4 indexed columns to the `flow` table for high-frequency queries, extend the existing `metadata` JSON for detailed info, and store certificate chains as PEM files using the existing payload-ref pattern.

---

## Database Schema Changes

### New Columns on `flow` Table

```sql
ALTER TABLE flow ADD COLUMN conn_reuse INTEGER DEFAULT 0;
ALTER TABLE flow ADD COLUMN proto_flags INTEGER DEFAULT 0;
ALTER TABLE flow ADD COLUMN push_status INTEGER;
ALTER TABLE flow ADD COLUMN cert_chain_ref TEXT;
```

Indexes for aggregate queries:

```sql
CREATE INDEX IF NOT EXISTS idx_flow_conn_reuse ON flow(conn_reuse);
CREATE INDEX IF NOT EXISTS idx_flow_proto_flags ON flow(proto_flags);
```

### `conn_reuse` — Connection Reuse Type

| Value | Meaning |
|-------|---------|
| 0 | New TCP connection |
| 1 | Keep-alive reuse (subsequent request on same client connection) |
| 2 | Connection pool reuse (checkout from OutboundConnectionPool) |

### `proto_flags` — Protocol Feature Bitmask

| Bit | Hex | Feature |
|-----|-----|---------|
| 0 | 0x0001 | HTTP/1.1 keep-alive active |
| 1 | 0x0002 | HTTP/1.1 pipelining (2nd+ request on same connection) |
| 2 | 0x0004 | H2 multiplexing |
| 3 | 0x0008 | H2 server push |
| 4 | 0x0010 | H2 flow control backpressure triggered |
| 5 | 0x0020 | WebSocket frame masking correctly applied |
| 6 | 0x0040 | TLS MITM interception |
| 7 | 0x0080 | TLS tunnel passthrough |
| 8 | 0x0100 | TLS handshake succeeded (client trusts cert) |
| 9 | 0x0200 | TLS handshake failed |
| 10 | 0x0400 | TLS handshake timeout |

### `push_status` — Push Promise Forwarding Status

| Value | Meaning |
|-------|---------|
| NULL | Not a push request |
| 0 | Capture-only (not forwarded to client) |
| 1 | Forwarded (PUSH_PROMISE frame written to client) |
| 2 | Forward failed (fell back to capture-only) |

### `cert_chain_ref` — Certificate Chain File Reference

File path relative to task folder, pointing to a PEM file containing the full certificate chain. NULL for non-TLS or tunnel-passthrough flows.

### Extended `metadata` JSON Fields

```json
{
  "connReusePoolKey": "example.com:443:ssl",
  "keepAliveRequestIndex": 3,
  "h2StreamId": 5,
  "h2PushParentStreamId": 1,
  "alpnNegotiated": "h2",
  "connectionHeader": "keep-alive",
  "tlsHandshakeError": "ALERT_CERTIFICATE_UNKNOWN",
  "certChainSummary": [
    {
      "subject": "CN=example.com",
      "issuer": "CN=Knot CA",
      "serial": "01:AB:...",
      "sha256": "a1b2c3...",
      "notBefore": "2026-01-01T00:00:00Z",
      "notAfter": "2027-01-01T00:00:00Z"
    }
  ]
}
```

---

## Certificate Chain Storage and Export

### Storage

Certificate chains are stored as PEM files following the existing payload-ref pattern:

```
{taskFileFolder}/certs/{flowId}.pem
```

A single PEM file contains the full chain, leaf certificate first:

```
-----BEGIN CERTIFICATE-----
(leaf: example.com)
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
(intermediate/root: Knot CA)
-----END CERTIFICATE-----
```

### Collection Timing

After TLS handshake completion (in `recordHandshakeComplete` / `recordTLSCertificateChain`):

1. Extract DER encoding from `NIOSSLCertificate` objects
2. Convert to PEM text, concatenate in chain order
3. Write to file, store path in `FlowRecord.certChainRef`
4. Extract summary info (subject/issuer/serial/sha256/validity) into `metadata.certChainSummary`

### Export Service

```swift
public final class CertExportService {

    public enum ExportFormat {
        case pem        // Original PEM text (full chain in one file)
        case derFiles   // Split into individual DER-encoded Data per certificate
    }

    public struct CertExportResult {
        public let flowId: String
        public let format: ExportFormat
        public let pemText: String?       // Set for .pem format
        public let derFiles: [DERFile]?   // Set for .derFiles format
    }

    public struct DERFile {
        public let subject: String     // "CN=example.com"
        public let data: Data          // DER encoding
        public let filename: String    // "example.com.der"
    }

    public enum CertExportError: Error {
        case noCertChain
        case fileNotFound(String)
        case parseFailed(String)
    }

    /// Save certificate chain as PEM file. Returns (relative path, summary array).
    public func saveCertChain(
        flowId: String,
        certificates: [NIOSSLCertificate]
    ) throws -> (ref: String, summary: [[String: String]])

    /// Export certificate chain for a flow.
    public func exportCertChain(
        certChainRef: String,
        format: ExportFormat
    ) -> Result<CertExportResult, CertExportError>
}
```

Certificate summary extraction uses the existing swift-certificates (`X509`) dependency to parse DER into structured fields (subject, issuer, serial, SHA-256 fingerprint, validity dates).

PKCS#12 export is not implemented in this iteration. The enum can be extended later.

---

## Data Collection Points

### HTTPCaptureHandler (HTTP/1.1)

| Timing | Fields Set |
|--------|-----------|
| `connectToServer` — pool checkout succeeds | `conn_reuse = 2`, metadata `connReusePoolKey` |
| `connectToServer` — reuses existing clientChannel | `conn_reuse = 1`, metadata `keepAliveRequestIndex++` |
| `connectToServer` — new connection | `conn_reuse = 0` |
| `shouldKeepAlive()` returns true | `proto_flags \|= 0x0001` |
| `resetForNextRequest` called (2nd+ request) | `proto_flags \|= 0x0002` |

### H2StreamCaptureHandler / H2ResponseRelayHandler (HTTP/2)

| Timing | Fields Set |
|--------|-----------|
| Stream created | `proto_flags \|= 0x0004`, metadata `h2StreamId` |
| `channelWritabilityChanged` toggles autoRead | `proto_flags \|= 0x0010` |

### H2PushRelayHandler (HTTP/2 Push)

| Timing | Fields Set |
|--------|-----------|
| Handler initialized | `proto_flags \|= 0x0008`, `push_status = 0` |
| `tryForwardPushPromise` succeeds | `push_status = 1` |
| `tryForwardPushPromise` fails | `push_status = 2` |
| Metadata supplement | `h2PushParentStreamId`, `alpnNegotiated` |

### WebSocketForwarder (WebSocket)

| Timing | Fields Set |
|--------|-----------|
| Frame forwarded with correct direction masking | `proto_flags \|= 0x0020` |

### MITMHandler / TLSPlugin (TLS)

| Timing | Fields Set |
|--------|-----------|
| Enters MITM path | `proto_flags \|= 0x0040` |
| Enters tunnel passthrough path | `proto_flags \|= 0x0080` |
| ALPN callback succeeds (handshake complete) | `proto_flags \|= 0x0100`, metadata `alpnNegotiated` |
| `errorCaught` detects certificate error | `proto_flags \|= 0x0200`, metadata `tlsHandshakeError` |
| Handshake timeout fires | `proto_flags \|= 0x0400` |
| Post-handshake certificate extraction | `cert_chain_ref`, metadata `certChainSummary` |

### Data Flow

```
Handlers call SessionRecorder setters (markConnectionReuse, addProtoFlag, etc.)
    ↓
SessionRecorder accumulates state in private fields
    ↓
recordClosed() → HTTPRecorder.buildFlowRecord() merges into FlowRecord
    ↓
FlowDAO.insert() persists to flow table (indexed columns + JSON metadata)
```

---

## SessionRecorder Interface

### New Types

```swift
public enum ConnectionReuseType {
    case new
    case keepAlive
    case pooled(key: String)
}

public struct ProtoFlag: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let keepAlive           = ProtoFlag(rawValue: 0x0001)
    public static let pipelining          = ProtoFlag(rawValue: 0x0002)
    public static let h2Multiplexing      = ProtoFlag(rawValue: 0x0004)
    public static let h2ServerPush        = ProtoFlag(rawValue: 0x0008)
    public static let h2FlowControl       = ProtoFlag(rawValue: 0x0010)
    public static let wsFrameMasked       = ProtoFlag(rawValue: 0x0020)
    public static let tlsMITM             = ProtoFlag(rawValue: 0x0040)
    public static let tlsTunnel           = ProtoFlag(rawValue: 0x0080)
    public static let tlsHandshakeOK      = ProtoFlag(rawValue: 0x0100)
    public static let tlsHandshakeFail    = ProtoFlag(rawValue: 0x0200)
    public static let tlsHandshakeTimeout = ProtoFlag(rawValue: 0x0400)
}

public enum PushForwardStatus: Int {
    case captureOnly = 0
    case forwarded = 1
    case failed = 2
}
```

### New Methods on SessionRecorder

```swift
public func markConnectionReuse(_ type: ConnectionReuseType)
public func addProtoFlag(_ flag: ProtoFlag)
public func markPushStatus(_ status: PushForwardStatus)
public func recordCertificateChain(_ certs: [NIOSSLCertificate])
public func setH2StreamId(_ id: Int)
```

### New Readable Properties

```swift
public var connReuse: Int { _connReuse }
public var protoFlags: Int { _protoFlags }
public var pushStatus: Int? { _pushStatus }
public var certChainRef: String? { _certChainRef }
public var keepAliveRequestIndex: Int { _keepAliveRequestIndex }
public var h2StreamId: Int? { _h2StreamId }
public var connReusePoolKey: String? { _connReusePoolKey }
```

All setters are simple in-memory operations. Persistence happens in `recordClosed()`.

---

## FlowRecord and FlowDAO Changes

### FlowRecord New Fields

```swift
public struct FlowRecord {
    // ... existing fields ...

    public var connReuse: Int = 0
    public var protoFlags: Int = 0
    public var pushStatus: Int? = nil
    public var certChainRef: String? = nil
}
```

### Schema Migration

```swift
static func migrateToV2(db: Connection) throws {
    try db.run(flowTable.addColumn(connReuseCol, defaultValue: 0))
    try db.run(flowTable.addColumn(protoFlagsCol, defaultValue: 0))
    try db.run(flowTable.addColumn(pushStatusCol))
    try db.run(flowTable.addColumn(certChainRefCol))
    try db.run(flowTable.createIndex(connReuseCol, ifNotExists: true))
    try db.run(flowTable.createIndex(protoFlagsCol, ifNotExists: true))
}
```

All new columns have defaults (0, 0, NULL, NULL), so existing rows are unaffected.

### Aggregate Query Examples

```sql
-- Connection reuse distribution
SELECT conn_reuse, COUNT(*) as cnt FROM flow GROUP BY conn_reuse;

-- Protocol feature distribution
SELECT
  COUNT(*) as total,
  SUM(CASE WHEN proto_flags & 0x0004 THEN 1 ELSE 0 END) as h2_count,
  SUM(CASE WHEN proto_flags & 0x0008 THEN 1 ELSE 0 END) as push_count,
  SUM(CASE WHEN proto_flags & 0x0010 THEN 1 ELSE 0 END) as flow_ctrl_count
FROM flow;

-- Push forwarding success rate
SELECT push_status, COUNT(*) FROM flow
WHERE push_status IS NOT NULL GROUP BY push_status;

-- TLS MITM vs tunnel ratio
SELECT
  SUM(CASE WHEN proto_flags & 0x0040 THEN 1 ELSE 0 END) as mitm,
  SUM(CASE WHEN proto_flags & 0x0080 THEN 1 ELSE 0 END) as tunnel
FROM flow;

-- Flows with certificate chains
SELECT * FROM flow WHERE cert_chain_ref IS NOT NULL;

-- Combined: H2 + pool reuse + handshake OK
SELECT * FROM flow
WHERE conn_reuse = 2 AND proto_flags & 0x0004 AND proto_flags & 0x0100;
```

---

## Error Handling and Edge Cases

### Certificate Write Failure

Disk errors during PEM file write must not block flow recording:
- `saveCertChain` catches errors internally, logs to `metadata["certSaveError"]`
- `certChainRef` remains nil; TLS proto_flags are still set normally
- Request/response recording is unaffected

### Schema Migration Compatibility

- `ALTER TABLE ADD COLUMN` is safe on existing SQLite tables
- All new columns have defaults, so old rows remain valid
- Version number check in `ProtocolSchema` ensures migration runs once

### Proto Flags Atomicity

Multiple handlers set `proto_flags` at different times (MITMHandler sets TLS bits, H2CaptureHandler sets H2 bits), all through the same `SessionRecorder` instance. All handlers run on the same NIO EventLoop, so flag writes are naturally serial. `addProtoFlag` is just `_protoFlags |= flag.rawValue` — no synchronization needed.

### Tunnel Passthrough Mode

In tunnel mode there is no decryption, so HTTP-layer data is unavailable:
- `conn_reuse = 0` (tunnels don't use the connection pool)
- `proto_flags = 0x0080` (only tlsTunnel bit)
- `cert_chain_ref = nil` (cannot extract certs without decryption; only passive SNI-level TLS sniff data available)
- metadata has `tlsSNI`, `tlsClientVersion` from passive sniffing

### Cleanup Strategy

Certificate PEM files live inside the task file folder (`{taskFileFolder}/certs/`). When a task is deleted, the entire folder is removed — no separate cert cleanup logic needed.

---

## File Structure

All source paths relative to `LocalPackages/TunnelServices/Sources/TunnelServices/`.

### New Files
- `Storage/CertExportService.swift` — Certificate chain save/export service

### Modified Files
- `Storage/Schema/ProtocolSchema.swift` — Schema migration (4 new columns + 2 indexes)
- `Storage/Model/FlowRecord.swift` — 4 new fields
- `Storage/DAO/FlowDAO.swift` — Insert/query updated for new columns
- `Plugins/HTTP1/HTTPRecorder.swift` — `buildFlowRecord()` merges new fields
- `Framework/SessionRecorder.swift` — New types (ProtoFlag, ConnectionReuseType, PushForwardStatus), new methods and properties
- `Plugins/HTTP1/HTTPCaptureHandler.swift` — Call `markConnectionReuse`, `addProtoFlag`
- `Plugins/HTTP2/HTTP2CaptureHandler.swift` — Call `addProtoFlag`, `markPushStatus`, `setH2StreamId`
- `Plugins/WebSocket/WebSocketCaptureHandler.swift` — Call `addProtoFlag(.wsFrameMasked)`
- `Plugins/TLS/MITMHandler.swift` — Call `addProtoFlag`, `recordCertificateChain`
- `Plugins/TLS/TLSPlugin.swift` — Call `addProtoFlag(.tlsTunnel)` or `addProtoFlag(.tlsMITM)`
- `Proxy/ConnectHandler.swift` — Call `addProtoFlag(.tlsMITM)` on intercept path
