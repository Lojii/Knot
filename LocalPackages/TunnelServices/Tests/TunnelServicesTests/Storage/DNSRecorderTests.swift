import XCTest
@testable import TunnelServices

final class DNSRecorderTests: XCTestCase {
    func testUDPDNSRecord() {
        let recorder = DNSRecorder(flowId: "dns_001", transport: .udp, serverIp: "8.8.8.8", serverPort: 53)
        recorder.recordQuery(domain: "example.com", queryType: "A", dnsId: 1234)
        recorder.recordResponse(
            responseCode: "NOERROR",
            answers: [["name": "example.com", "type": "A", "ttl": 300, "data": "93.184.216.34"]],
            authorities: [], additionals: []
        )
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "DNS")
        XCTAssertEqual(record.host, "example.com")
        XCTAssertEqual(record.port, 53)
        XCTAssertEqual(record.searchKey1, "A")
        XCTAssertEqual(record.searchKey2, "example.com")
        XCTAssertEqual(record.searchKey3, "93.184.216.34")
        XCTAssertEqual(record.searchKey4, "NOERROR")
        XCTAssertEqual(record.metadata["transport"] as? String, "udp")
        XCTAssertEqual(record.summary, "A example.com → 93.184.216.34")
    }

    func testDoHDNSRecord() {
        let recorder = DNSRecorder(flowId: "dns_002", transport: .doh, serverIp: "1.1.1.1", serverPort: 443)
        recorder.httpFlowId = "http_042"
        recorder.recordQuery(domain: "api.example.com", queryType: "AAAA", dnsId: 5678)
        recorder.recordResponse(responseCode: "NXDOMAIN", answers: [], authorities: [], additionals: [])
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.metadata["transport"] as? String, "doh")
        XCTAssertEqual(record.metadata["httpFlowId"] as? String, "http_042")
        XCTAssertEqual(record.searchKey3, "")
        XCTAssertEqual(record.searchKey4, "NXDOMAIN")
        XCTAssertTrue(record.summary.contains("NXDOMAIN"))
    }

    func testSearchKeyMapping() {
        XCTAssertEqual(DNSRecorder.searchKeyMapping.key1, "queryType")
        XCTAssertEqual(DNSRecorder.searchKeyMapping.key2, "domain")
        XCTAssertEqual(DNSRecorder.searchKeyMapping.key3, "firstAnswer")
        XCTAssertEqual(DNSRecorder.searchKeyMapping.key4, "responseCode")
    }

    func testMultipleAnswers() {
        let recorder = DNSRecorder(flowId: "dns_003", transport: .udp, serverIp: "8.8.8.8", serverPort: 53)
        recorder.recordQuery(domain: "cdn.example.com", queryType: "A", dnsId: 9999)
        recorder.recordResponse(
            responseCode: "NOERROR",
            answers: [
                ["name": "cdn.example.com", "type": "A", "data": "1.1.1.1"],
                ["name": "cdn.example.com", "type": "A", "data": "2.2.2.2"]
            ],
            authorities: [], additionals: []
        )
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.searchKey3, "1.1.1.1") // first answer only
        let answers = record.metadata["answers"] as? [[String: Any]]
        XCTAssertEqual(answers?.count, 2)
    }
}
