import Foundation

/// Extracts searchable text from a binary data stream.
/// Accumulates bytes up to `maxSize`, then stops.
/// Returns UTF-8 decoded text, or nil if the content is binary (invalid UTF-8).
public class TextAccumulator {
    private var buffer: [UInt8] = []
    private let maxSize: Int

    public init(maxSize: Int) {
        self.maxSize = maxSize
    }

    /// Append data chunk. Stops accumulating once maxSize is reached.
    public func append(_ data: Data) {
        guard buffer.count < maxSize else { return }
        let remaining = maxSize - buffer.count
        if data.count <= remaining {
            buffer.append(contentsOf: data)
        } else {
            buffer.append(contentsOf: data.prefix(remaining))
        }
    }

    /// Attempt to decode accumulated bytes as UTF-8.
    /// Returns nil if buffer is empty or contains invalid UTF-8.
    public var text: String? {
        guard !buffer.isEmpty else { return nil }
        return String(bytes: buffer, encoding: .utf8)
    }
}
