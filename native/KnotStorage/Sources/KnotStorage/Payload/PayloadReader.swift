import Foundation

/// Streaming file reader. Never loads entire file into memory.
/// Supports range reads (for UI preview) and chunk iteration (for export/processing).
public class PayloadReader {
    private let fileHandle: FileHandle
    public let size: Int64
    private let chunkSize: Int

    public init(filePath: String, chunkSize: Int = 64 * 1024) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
        self.size = (attrs[.size] as? Int64) ?? 0
        self.fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
        self.chunkSize = chunkSize
    }

    /// Read a specific byte range (for UI paged preview)
    public func read(offset: Int64, length: Int) -> Data {
        fileHandle.seek(toFileOffset: UInt64(offset))
        let toRead = min(length, Int(size - offset))
        guard toRead > 0 else { return Data() }
        return fileHandle.readData(ofLength: toRead)
    }

    /// Iterate over file in chunks (for export, streaming, processing)
    public func chunks() -> ChunkSequence {
        fileHandle.seek(toFileOffset: 0)
        return ChunkSequence(fileHandle: fileHandle, fileSize: size, chunkSize: chunkSize)
    }

    public func close() {
        fileHandle.closeFile()
    }

    // MARK: - ChunkSequence

    public struct ChunkSequence: Sequence {
        let fileHandle: FileHandle
        let fileSize: Int64
        let chunkSize: Int

        public func makeIterator() -> ChunkIterator {
            fileHandle.seek(toFileOffset: 0)
            return ChunkIterator(fileHandle: fileHandle, remaining: fileSize, chunkSize: chunkSize)
        }
    }

    public struct ChunkIterator: IteratorProtocol {
        let fileHandle: FileHandle
        var remaining: Int64
        let chunkSize: Int

        public mutating func next() -> Data? {
            guard remaining > 0 else { return nil }
            let toRead = min(Int(remaining), chunkSize)
            let data = fileHandle.readData(ofLength: toRead)
            guard !data.isEmpty else { return nil }
            remaining -= Int64(data.count)
            return data
        }
    }
}
