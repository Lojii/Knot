import XCTest
import KnotStorage
@testable import TunnelServices

final class HTTPRecorderTests: XCTestCase {
    func testBuildFlowRecordBasic() {
        let recorder = HTTPRecorder(flowId: "test_0001", host: "api.example.com", port: 443)
        recorder.recordRequestHead(method: "GET", uri: "/api/users", httpVersion: "HTTP/1.1",
                                   headers: [("Host", "api.example.com"), ("Accept", "application/json")])
        recorder.recordResponseHead(statusCode: 200,
                                    headers: [("Content-Type", "application/json"), ("Content-Encoding", "gzip")])

        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "HTTP")
        XCTAssertEqual(record.host, "api.example.com")
        XCTAssertEqual(record.port, 443)
        XCTAssertEqual(record.searchKey1, "GET")
        XCTAssertEqual(record.searchKey2, "/api/users")
        XCTAssertEqual(record.searchKey3, "200")
        XCTAssertEqual(record.searchKey4, "application/json")
        XCTAssertEqual(record.summary, "GET /api/users → 200")
    }

    func testBuildFlowRecordPOST() {
        let recorder = HTTPRecorder(flowId: "test_0002", host: "api.example.com", port: 443)
        recorder.recordRequestHead(method: "POST", uri: "/api/data", httpVersion: "HTTP/1.1", headers: [])
        recorder.recordResponseHead(statusCode: 201, headers: [("Content-Type", "text/plain")])

        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.searchKey1, "POST")
        XCTAssertEqual(record.searchKey3, "201")
        XCTAssertEqual(record.summary, "POST /api/data → 201")
    }

    func testTimingsRecorded() {
        let recorder = HTTPRecorder(flowId: "test_0003", host: "test.com", port: 80)
        recorder.recordRequestHead(method: "GET", uri: "/", httpVersion: "HTTP/1.1", headers: [])
        recorder.recordConnected(at: 1000.5)
        recorder.recordTLSDone(at: 1001.0)
        recorder.recordRequestEnd(at: 1001.5)
        recorder.recordResponseStart(at: 1002.0)
        recorder.recordResponseHead(statusCode: 200, headers: [])
        recorder.recordResponseEnd(at: 1003.0)

        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.connectedAt, 1000.5)
        XCTAssertEqual(record.tlsDoneAt, 1001.0)
        XCTAssertEqual(record.reqEndAt, 1001.5)
        XCTAssertEqual(record.rspStartAt, 1002.0)
        XCTAssertNotNil(record.endedAt)
    }

    func testTrafficTracking() {
        let recorder = HTTPRecorder(flowId: "test_0004", host: "test.com", port: 80)
        recorder.recordRequestHead(method: "GET", uri: "/", httpVersion: "HTTP/1.1", headers: [])
        recorder.addUpload(bytes: 100)
        recorder.addUpload(bytes: 50)
        recorder.addDownload(bytes: 2048)

        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.uploadBytes, 150)
        XCTAssertEqual(record.downloadBytes, 2048)
    }

    func testMetadataContainsHeaders() {
        let recorder = HTTPRecorder(flowId: "test_0005", host: "test.com", port: 80)
        recorder.recordRequestHead(method: "GET", uri: "/", httpVersion: "HTTP/1.1",
                                   headers: [("Authorization", "Bearer xxx")])
        recorder.recordResponseHead(statusCode: 200, headers: [("X-Custom", "value")])

        let record = recorder.buildFlowRecord()
        let metadata = record.metadata
        XCTAssertNotNil(metadata["httpVersion"])
        XCTAssertNotNil(metadata["reqHeaders"])
        XCTAssertNotNil(metadata["rspHeaders"])
    }

    func testSearchKeyMapping() {
        let mapping = HTTPRecorder.searchKeyMapping
        XCTAssertEqual(mapping.key1, "method")
        XCTAssertEqual(mapping.key2, "uri")
        XCTAssertEqual(mapping.key3, "statusCode")
        XCTAssertEqual(mapping.key4, "contentType")
    }

    func testErrorRecording() {
        let recorder = HTTPRecorder(flowId: "test_0006", host: "test.com", port: 80)
        recorder.recordRequestHead(method: "GET", uri: "/fail", httpVersion: "HTTP/1.1", headers: [])
        recorder.recordError("Connection reset by peer")

        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.errorMessage, "Connection reset by peer")
    }

    func testProtocolOverrideH2() {
        let recorder = HTTPRecorder(flowId: "h2_0001", host: "api.example.com", port: 443,
                                    protocolOverride: "H2", extraMetadata: ["streamId": 5])
        recorder.recordRequestHead(method: "GET", uri: "/api", httpVersion: "HTTP/2", headers: [])
        recorder.recordResponseHead(statusCode: 200, headers: [])
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "H2")
        XCTAssertEqual(record.metadata["streamId"] as? Int, 5)
    }

    func testProtocolOverrideH3() {
        let recorder = HTTPRecorder(flowId: "h3_0001", host: "api.example.com", port: 443,
                                    protocolOverride: "H3", extraMetadata: ["quicVersion": "1"])
        recorder.recordRequestHead(method: "POST", uri: "/data", httpVersion: "HTTP/3", headers: [])
        recorder.recordResponseHead(statusCode: 201, headers: [])
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "H3")
    }
}
