import XCTest
import SQLite
@testable import TunnelServices

final class GRPCRecorderTests: XCTestCase {
    var helper: StorageTestHelper!
    var dbGroup: TaskDatabaseGroup!

    override func setUp() {
        helper = StorageTestHelper()
        let mgr = DatabaseManager(rootPath: helper.tempDir)
        dbGroup = try! mgr.openTask(1)
    }
    override func tearDown() { helper = nil }

    func testUnaryRPC() {
        let recorder = GRPCRecorder(flowId: "grpc_001", host: "api.example.com", port: 443,
                                    path: "/UserService/GetUser", dbGroup: dbGroup)
        recorder.recordRequestMessage(data: Data("{\"id\":1}".utf8), sequence: 0)
        recorder.recordResponseMessage(data: Data("{\"name\":\"Alice\"}".utf8), sequence: 0)
        recorder.recordClosed(grpcStatus: 0, grpcMessage: "OK", trailers: [("grpc-status", "0")])

        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.protocolName, "gRPC")
        XCTAssertEqual(record.searchKey1, "GetUser")
        XCTAssertEqual(record.searchKey2, "UserService")
        XCTAssertEqual(record.searchKey3, "0")
        XCTAssertEqual(record.searchKey4, "OK")
        XCTAssertEqual(record.summary, "UserService/GetUser → OK")
    }

    func testStreamingRPC() {
        let recorder = GRPCRecorder(flowId: "grpc_002", host: "api.example.com", port: 443,
                                    path: "/ChatService/StreamMessages", dbGroup: dbGroup)
        for i in 0..<3 {
            recorder.recordResponseMessage(data: Data("msg\(i)".utf8), sequence: i)
        }
        recorder.recordClosed(grpcStatus: 0, grpcMessage: "OK", trailers: [])

        dbGroup.decodedWriteQueue.sync {}
        let entries = try! DecodedEntryDAO.findAll(db: dbGroup.decoded, flowId: "grpc_002")
        XCTAssertEqual(entries.count, 3)
    }

    func testPathParsing() {
        let recorder = GRPCRecorder(flowId: "grpc_003", host: "h", port: 443,
                                    path: "/com.example.MyService/DoThing", dbGroup: dbGroup)
        recorder.recordClosed(grpcStatus: 0, grpcMessage: "OK", trailers: [])
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.searchKey1, "DoThing")
        XCTAssertEqual(record.searchKey2, "com.example.MyService")
    }

    func testPreliminaryFlowInserted() {
        let _ = GRPCRecorder(flowId: "grpc_004", host: "h", port: 443,
                             path: "/Svc/Method", dbGroup: dbGroup)
        dbGroup.protoWriteQueue.sync {}
        let flow = try! FlowDAO.find(db: dbGroup.proto, flowId: "grpc_004")
        XCTAssertNotNil(flow)
        XCTAssertEqual(flow?.status, .inProgress)
    }

    func testSearchKeyMapping() {
        XCTAssertEqual(GRPCRecorder.searchKeyMapping.key1, "method")
        XCTAssertEqual(GRPCRecorder.searchKeyMapping.key2, "service")
    }

    func testErrorStatus() {
        let recorder = GRPCRecorder(flowId: "grpc_005", host: "h", port: 443,
                                    path: "/Svc/Fail", dbGroup: dbGroup)
        recorder.recordClosed(grpcStatus: 13, grpcMessage: "INTERNAL", trailers: [])
        let record = recorder.buildFlowRecord()
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.searchKey3, "13")
        XCTAssertEqual(record.searchKey4, "INTERNAL")
    }
}
