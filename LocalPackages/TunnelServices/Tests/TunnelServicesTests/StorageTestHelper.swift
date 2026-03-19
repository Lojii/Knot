import Foundation
import SQLite
@testable import TunnelServices

/// Provides temp directories and cleanup for storage tests
class StorageTestHelper {
    let tempDir: String

    init() {
        tempDir = NSTemporaryDirectory() + "KnotTests_\(UUID().uuidString)"
        try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    func createTempDB(name: String = "test.db") throws -> Connection {
        let path = (tempDir as NSString).appendingPathComponent(name)
        return try Connection(path)
    }
}
