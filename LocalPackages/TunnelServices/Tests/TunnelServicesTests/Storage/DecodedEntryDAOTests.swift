import XCTest
import SQLite
@testable import TunnelServices

final class DecodedEntryDAOTests: XCTestCase {
    var db: Connection!
    var helper: StorageTestHelper!

    override func setUp() {
        helper = StorageTestHelper()
        db = try! helper.createTempDB(name: "decoded.db")
        try! DecodedSchema.create(db)
    }
    override func tearDown() { helper = nil }

    func testInsertAndFind() throws {
        let entry = DecodedEntry(flowId: "f_001", direction: 1, originalEncoding: "gzip",
            decodedType: "text/html", decodedSize: 100, payloadRef: "f_001_rsp.html",
            searchText: "Hello World", decodedAt: 1000)
        try DecodedEntryDAO.insert(db: db, entry: entry)
        let found = try DecodedEntryDAO.find(db: db, flowId: "f_001", direction: 1)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.decodedType, "text/html")
        XCTAssertEqual(found?.decodedSize, 100)
    }

    func testInlineSmallPayload() throws {
        let smallData = Data("tiny".utf8)
        let entry = DecodedEntry(flowId: "f_002", direction: 0,
            decodedType: "text/plain", decodedSize: Int64(smallData.count),
            isInline: true, inlineData: smallData, searchText: "tiny", decodedAt: 1000)
        try DecodedEntryDAO.insert(db: db, entry: entry)
        let found = try DecodedEntryDAO.find(db: db, flowId: "f_002", direction: 0)
        XCTAssertEqual(found?.isInline, true)
        // Note: inlineData retrieval depends on SQLite.swift BLOB handling
    }

    func testFTSSearch() throws {
        let entry1 = DecodedEntry(flowId: "f_010", direction: 1,
            decodedType: "text/html", decodedSize: 50,
            searchText: "login page with username field", decodedAt: 1000)
        let entry2 = DecodedEntry(flowId: "f_011", direction: 1,
            decodedType: "application/json", decodedSize: 30,
            searchText: "api response with token", decodedAt: 1001)
        try DecodedEntryDAO.insert(db: db, entry: entry1)
        try DecodedEntryDAO.insert(db: db, entry: entry2)

        let results = try DecodedEntryDAO.searchFullText(db: db, query: "username", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].flowId, "f_010")
    }
}
