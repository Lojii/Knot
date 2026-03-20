import NIOCore
import Darwin

/// Codec for the UDP destination address header prepended to every forwarded UDP datagram.
///
/// Header format:
/// ```
/// [addrType(1)] [address(variable)] [port(2, big-endian)] [payload...]
///
/// addrType:
///   0x01 = IPv4  — 4-byte address
///   0x03 = Domain — 1-byte length + domain string bytes
///   0x04 = IPv6  — 16-byte address
/// ```
public enum UDPHeaderCodec {

    // MARK: - Constants

    public static let addrTypeIPv4:   UInt8 = 0x01
    public static let addrTypeDomain: UInt8 = 0x03
    public static let addrTypeIPv6:   UInt8 = 0x04

    // MARK: - Decoded result

    public struct DecodedHeader {
        public let host: String
        public let port: Int
        public var payload: ByteBuffer

        public init(host: String, port: Int, payload: ByteBuffer) {
            self.host    = host
            self.port    = port
            self.payload = payload
        }
    }

    // MARK: - Encode

    /// Encode a destination address + port header into `buffer`.
    ///
    /// - Parameters:
    ///   - host: IPv4 dotted-decimal, IPv6 colon-hex, or domain name string.
    ///   - port: Destination port (0–65535).
    ///   - buffer: Buffer to write into (header is appended at the current writerIndex).
    public static func encode(host: String, port: Int, into buffer: inout ByteBuffer) {
        // Try IPv4
        var addr4 = in_addr()
        if inet_pton(AF_INET, host, &addr4) == 1 {
            buffer.writeInteger(addrTypeIPv4)
            withUnsafeBytes(of: addr4.s_addr) { buffer.writeBytes($0) }   // already network-byte-order
            buffer.writeInteger(UInt16(port & 0xFFFF))
            return
        }

        // Try IPv6
        var addr6 = in6_addr()
        if inet_pton(AF_INET6, host, &addr6) == 1 {
            buffer.writeInteger(addrTypeIPv6)
            _ = withUnsafeBytes(of: addr6.__u6_addr.__u6_addr8) { buffer.writeBytes($0) }
            buffer.writeInteger(UInt16(port & 0xFFFF))
            return
        }

        // Domain
        let domainBytes = Array(host.utf8)
        buffer.writeInteger(addrTypeDomain)
        buffer.writeInteger(UInt8(domainBytes.count & 0xFF))
        buffer.writeBytes(domainBytes)
        buffer.writeInteger(UInt16(port & 0xFFFF))
    }

    // MARK: - Decode

    /// Decode a destination address header from `buffer`, advancing the readerIndex past the header.
    ///
    /// - Parameter buffer: Buffer whose readerIndex points at the start of the header.
    /// - Returns: A `DecodedHeader` on success, or `nil` if the buffer is malformed or truncated.
    public static func decode(from buffer: inout ByteBuffer) -> DecodedHeader? {
        // Work on a copy so readerIndex is only advanced on full success.
        var buf = buffer

        guard let addrType: UInt8 = buf.readInteger() else { return nil }

        let host: String
        switch addrType {

        case addrTypeIPv4:
            guard let bytes = buf.readBytes(length: 4) else { return nil }
            host = bytes.map { String($0) }.joined(separator: ".")

        case addrTypeIPv6:
            guard let bytes = buf.readBytes(length: 16) else { return nil }
            // Format as eight colon-separated 16-bit groups in hex.
            var groups: [String] = []
            for i in stride(from: 0, to: 16, by: 2) {
                let value = (UInt16(bytes[i]) << 8) | UInt16(bytes[i + 1])
                groups.append(String(format: "%x", value))
            }
            host = groups.joined(separator: ":")

        case addrTypeDomain:
            guard let length: UInt8 = buf.readInteger() else { return nil }
            guard let domainBytes = buf.readBytes(length: Int(length)),
                  let domain = String(bytes: domainBytes, encoding: .utf8) else { return nil }
            host = domain

        default:
            return nil
        }

        guard let rawPort: UInt16 = buf.readInteger() else { return nil }
        let port = Int(rawPort)

        // All remaining bytes in `buf` are the payload.
        let payload = buf.readSlice(length: buf.readableBytes) ?? buf

        // Success — advance the original buffer's readerIndex.
        buffer = buf

        return DecodedHeader(host: host, port: port, payload: payload)
    }
}
