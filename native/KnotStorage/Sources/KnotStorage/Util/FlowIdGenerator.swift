import Foundation

/// Thread-safe generator for unique flow identifiers.
/// Format: {timestamp_ms}_{4-digit_sequence}, e.g. "1679012345678_0001"
/// One instance per CaptureTask. The timestamp ensures global ordering;
/// the sequence handles multiple flows within the same millisecond.
public class FlowIdGenerator {
    private let lock = NSLock()
    private var lastTimestamp: Int64 = 0
    private var sequence: Int = 0

    public init() {}

    public func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if now == lastTimestamp {
            sequence += 1
        } else {
            lastTimestamp = now
            sequence = 1
        }
        return String(format: "%lld_%04d", lastTimestamp, sequence)
    }
}
