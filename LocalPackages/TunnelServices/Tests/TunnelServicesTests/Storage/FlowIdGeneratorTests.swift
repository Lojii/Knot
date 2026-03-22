import XCTest
import KnotStorage
@testable import TunnelServices

final class FlowIdGeneratorTests: XCTestCase {
    func testUniqueIds() {
        let gen = FlowIdGenerator()
        var ids = Set<String>()
        for _ in 0..<1000 {
            ids.insert(gen.next())
        }
        XCTAssertEqual(ids.count, 1000, "All IDs should be unique")
    }

    func testFormat() {
        let gen = FlowIdGenerator()
        let id = gen.next()
        let parts = id.split(separator: "_")
        XCTAssertEqual(parts.count, 2)
        XCTAssertNotNil(Int64(parts[0]))       // timestamp portion is numeric
        XCTAssertEqual(parts[1].count, 4)       // zero-padded 4 digits
    }

    func testThreadSafety() {
        let gen = FlowIdGenerator()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test", attributes: .concurrent)
        var allIds: [String] = []
        let lock = NSLock()

        for _ in 0..<100 {
            group.enter()
            queue.async {
                let id = gen.next()
                lock.lock()
                allIds.append(id)
                lock.unlock()
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(Set(allIds).count, 100, "All IDs from concurrent generation should be unique")
    }

    func testMonotonicallyIncreasing() {
        let gen = FlowIdGenerator()
        var prev = gen.next()
        for _ in 0..<100 {
            let curr = gen.next()
            XCTAssertTrue(curr > prev, "IDs should be lexicographically increasing")
            prev = curr
        }
    }
}
