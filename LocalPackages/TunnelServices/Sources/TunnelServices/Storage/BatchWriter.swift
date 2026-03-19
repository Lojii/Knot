import Foundation
import SQLite

/// Batched transaction writer for transport.db.
/// Accumulates rows and commits in bulk (by count or timer) to reduce transaction overhead.
public class BatchWriter {
    private let db: Connection
    private let queue: DispatchQueue
    private var pendingRows: [PacketRow] = []
    private let batchSize: Int
    private var flushTimer: DispatchSourceTimer?

    public init(db: Connection, queue: DispatchQueue, batchSize: Int = 50, flushInterval: TimeInterval = 0.1) {
        self.db = db
        self.queue = queue
        self.batchSize = batchSize
        self.pendingRows.reserveCapacity(batchSize)

        // Set up periodic flush timer
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        timer.resume()
        flushTimer = timer
    }

    /// Enqueue a row for batch insert. Called from any thread, dispatched to serial queue.
    public func enqueue(_ row: PacketRow) {
        queue.async { [self] in
            pendingRows.append(row)
            if pendingRows.count >= batchSize {
                flush()
            }
        }
    }

    /// Flush all pending rows in a single transaction. Must be called on `queue`.
    private func flush() {
        guard !pendingRows.isEmpty else { return }
        let batch = pendingRows
        pendingRows.removeAll(keepingCapacity: true)
        try? PacketDAO.insertBatch(db: db, rows: batch)
    }

    /// Stop timer and flush remaining rows. Synchronous — blocks until done.
    public func finalize() {
        flushTimer?.cancel()
        flushTimer = nil
        queue.sync { [self] in
            flush()
        }
    }

    deinit {
        flushTimer?.cancel()
    }
}
