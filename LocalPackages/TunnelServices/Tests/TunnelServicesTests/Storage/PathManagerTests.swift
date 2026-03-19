import XCTest
@testable import TunnelServices

final class PathManagerTests: XCTestCase {
    var helper: StorageTestHelper!

    override func setUp() { helper = StorageTestHelper() }
    override func tearDown() { helper = nil }

    func testCatalogDBPath() {
        let path = PathManager.catalogDBPath(root: helper.tempDir)
        XCTAssertEqual(path, "\(helper.tempDir)/catalog.db")
    }

    func testTaskDirectory() {
        let path = PathManager.taskDirectory(42, root: helper.tempDir)
        XCTAssertEqual(path, "\(helper.tempDir)/tasks/42")
    }

    func testTransportDBPath() {
        let path = PathManager.transportDBPath(42, root: helper.tempDir)
        XCTAssertTrue(path.hasSuffix("/tasks/42/transport.db"))
    }

    func testProtocolDBPath() {
        let path = PathManager.protocolDBPath(42, root: helper.tempDir)
        XCTAssertTrue(path.hasSuffix("/tasks/42/protocol.db"))
    }

    func testDecodedDBPath() {
        let path = PathManager.decodedDBPath(42, root: helper.tempDir)
        XCTAssertTrue(path.hasSuffix("/tasks/42/decoded.db"))
    }

    func testStateDBPath() {
        let path = PathManager.stateDBPath(42, root: helper.tempDir)
        XCTAssertTrue(path.hasSuffix("/tasks/42/state.db"))
    }

    func testRawPayloadPath() {
        let path = PathManager.rawPayloadPath(taskId: 1, ref: "123_0001_req.bin", root: helper.tempDir)
        XCTAssertTrue(path.hasSuffix("/tasks/1/payloads/raw/123_0001_req.bin"))
    }

    func testDecodedPayloadPath() {
        let path = PathManager.decodedPayloadPath(taskId: 1, flowId: "123_0001", direction: .request, ext: "json", root: helper.tempDir)
        XCTAssertTrue(path.hasSuffix("/tasks/1/payloads/decoded/123_0001_req.json"))
    }

    func testModifiedPayloadPath() {
        let path = PathManager.modifiedPayloadPath(taskId: 1, flowId: "123_0001", version: 2, direction: .response, root: helper.tempDir)
        XCTAssertTrue(path.hasSuffix("/tasks/1/payloads/modified/123_0001_v2_rsp.bin"))
    }

    func testPayloadsDirectory() {
        let path = PathManager.payloadsDirectory(1, root: helper.tempDir)
        XCTAssertTrue(path.hasSuffix("/tasks/1/payloads"))
    }

    func testEnsureTaskDirectories() throws {
        try PathManager.ensureTaskDirectories(99, root: helper.tempDir)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/99"))
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/99/payloads/raw"))
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/99/payloads/decoded"))
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/99/payloads/modified"))
        XCTAssertTrue(fm.fileExists(atPath: "\(helper.tempDir)/tasks/99/export"))
    }

    func testEnsureTaskDirectoriesIdempotent() throws {
        try PathManager.ensureTaskDirectories(99, root: helper.tempDir)
        try PathManager.ensureTaskDirectories(99, root: helper.tempDir) // should not throw
    }
}
