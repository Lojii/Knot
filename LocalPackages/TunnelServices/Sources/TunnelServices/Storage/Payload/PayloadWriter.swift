import Foundation
import NIOCore

/// Streaming file writer with configurable flush buffer.
/// Never holds the complete payload in memory.
public class PayloadWriter {
    private let fileHandle: FileHandle
    public let filePath: String
    public private(set) var totalBytesWritten: Int64 = 0

    private var buffer: Data
    private let flushThreshold: Int

    /// Creates a new writer. The file is created empty on disk immediately.
    /// - Parameters:
    ///   - directory: Directory to create the file in (must exist)
    ///   - fileName: Name of the file to create
    ///   - flushThreshold: Bytes to accumulate before flushing to disk (default 32KB)
    public init(directory: String, fileName: String, flushThreshold: Int = 32 * 1024) throws {
        let path = (directory as NSString).appendingPathComponent(fileName)
        self.filePath = path
        self.flushThreshold = flushThreshold
        self.buffer = Data(capacity: flushThreshold)

        // Ensure directory exists, then create empty file on disk
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    }

    /// Append raw Data to the writer
    public func append(_ data: Data) throws {
        buffer.append(data)
        totalBytesWritten += Int64(data.count)
        if buffer.count >= flushThreshold {
            try flush()
        }
    }

    /// Append from NIO ByteBuffer (zero-copy read)
    public func append(_ byteBuffer: ByteBuffer) throws {
        let readable = byteBuffer.readableBytesView
        buffer.append(contentsOf: readable)
        totalBytesWritten += Int64(readable.count)
        if buffer.count >= flushThreshold {
            try flush()
        }
    }

    /// Flush buffer to disk
    public func flush() throws {
        guard !buffer.isEmpty else { return }
        fileHandle.write(buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    /// Flush remaining buffer and close file handle
    public func close() throws {
        try flush()
        fileHandle.closeFile()
    }
}
