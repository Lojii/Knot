import Foundation
import Compression

/// Protocol for streaming decompression
public protocol DecompressStream {
    func decompress(_ chunk: Data) throws -> Data
    func finalize() throws
}

/// Passthrough for uncompressed data
public class IdentityStream: DecompressStream {
    public init() {}
    public func decompress(_ chunk: Data) throws -> Data { chunk }
    public func finalize() throws {}
}

/// Streaming decompressor using Apple's Compression framework
public class CompressionDecompressStream: DecompressStream {
    private var streamStorage: UnsafeMutablePointer<compression_stream>
    private let outputBuffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int = 65536
    private var initialized = true

    public init(algorithm: compression_algorithm) throws {
        outputBuffer = .allocate(capacity: 65536)
        streamStorage = .allocate(capacity: 1)
        streamStorage.initialize(to: compression_stream(
            dst_ptr: outputBuffer,
            dst_size: 0,
            src_ptr: outputBuffer,
            src_size: 0,
            state: nil
        ))
        let status = compression_stream_init(streamStorage, COMPRESSION_STREAM_DECODE, algorithm)
        guard status == COMPRESSION_STATUS_OK else {
            streamStorage.deallocate()
            outputBuffer.deallocate()
            throw DecompressError.initFailed
        }
    }

    public func decompress(_ chunk: Data) throws -> Data {
        var result = Data()
        try chunk.withUnsafeBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            streamStorage.pointee.src_ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            streamStorage.pointee.src_size = chunk.count

            repeat {
                streamStorage.pointee.dst_ptr = outputBuffer
                streamStorage.pointee.dst_size = bufferSize
                let status = compression_stream_process(streamStorage, 0)

                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - streamStorage.pointee.dst_size
                    if produced > 0 {
                        result.append(outputBuffer, count: produced)
                    }
                case COMPRESSION_STATUS_ERROR:
                    throw DecompressError.decompressFailed
                default:
                    break
                }
            } while streamStorage.pointee.src_size > 0
        }
        return result
    }

    public func finalize() throws {
        guard initialized else { return }
        initialized = false
        compression_stream_destroy(streamStorage)
        streamStorage.deallocate()
        outputBuffer.deallocate()
    }

    deinit {
        if initialized {
            compression_stream_destroy(streamStorage)
            streamStorage.deallocate()
            outputBuffer.deallocate()
        }
    }
}

public enum DecompressError: Error {
    case initFailed
    case decompressFailed
    case unsupportedEncoding(String)
}

/// Factory for creating the right decompressor
public func makeDecompressStream(encoding: String) throws -> DecompressStream {
    switch encoding.lowercased() {
    case "identity", "", "none":
        return IdentityStream()
    case "deflate", "zlib":
        return try CompressionDecompressStream(algorithm: COMPRESSION_ZLIB)
    case "gzip":
        // Note: Apple's COMPRESSION_ZLIB handles both raw deflate and gzip
        return try CompressionDecompressStream(algorithm: COMPRESSION_ZLIB)
    case "lz4":
        return try CompressionDecompressStream(algorithm: COMPRESSION_LZ4)
    case "lzma":
        return try CompressionDecompressStream(algorithm: COMPRESSION_LZMA)
    default:
        throw DecompressError.unsupportedEncoding(encoding)
    }
}

// MARK: - Data compression helper (used in tests)

extension Data {
    /// Compress using zlib (COMPRESSION_ZLIB) for testing
    func compressed() throws -> Data {
        let bufferSize = 65536
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { outputBuffer.deallocate() }

        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        streamPtr.initialize(to: compression_stream(
            dst_ptr: outputBuffer,
            dst_size: 0,
            src_ptr: outputBuffer,
            src_size: 0,
            state: nil
        ))
        defer {
            compression_stream_destroy(streamPtr)
            streamPtr.deallocate()
        }

        let status = compression_stream_init(streamPtr, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { throw DecompressError.initFailed }

        var result = Data()
        self.withUnsafeBytes { rawPtr in
            guard let baseAddress = rawPtr.baseAddress else { return }
            streamPtr.pointee.src_ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            streamPtr.pointee.src_size = self.count

            repeat {
                streamPtr.pointee.dst_ptr = outputBuffer
                streamPtr.pointee.dst_size = bufferSize
                let _ = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - streamPtr.pointee.dst_size
                if produced > 0 { result.append(outputBuffer, count: produced) }
            } while streamPtr.pointee.dst_size == 0
        }
        return result
    }
}
