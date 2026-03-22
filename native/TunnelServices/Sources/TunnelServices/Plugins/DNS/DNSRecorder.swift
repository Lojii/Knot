import Foundation
import KnotStorage

public enum DNSTransport: String {
    case udp = "udp"
    case doh = "doh"
}

public class DNSRecorder: ProtocolRecorder {
    public static let protocolName = "DNS"
    public static let searchKeyMapping = SearchKeyMapping(
        key1: "queryType", key2: "domain", key3: "firstAnswer", key4: "responseCode"
    )

    private let flowId: String
    private let transport: DNSTransport
    private let serverIp: String
    private let serverPort: Int
    private let startedAt: TimeInterval
    public var httpFlowId: String?  // only for DoH

    // Query data
    private var domain: String = ""
    private var queryType: String = ""
    private var dnsId: UInt16 = 0
    private var questions: [[String: Any]] = []

    // Response data
    private var responseCode: String = ""
    private var answers: [[String: Any]] = []
    private var authorities: [[String: Any]] = []
    private var additionals: [[String: Any]] = []
    private var endedAt: TimeInterval?

    public init(flowId: String, transport: DNSTransport, serverIp: String, serverPort: Int) {
        self.flowId = flowId
        self.transport = transport
        self.serverIp = serverIp
        self.serverPort = serverPort
        self.startedAt = Date().timeIntervalSince1970
    }

    public func recordQuery(domain: String, queryType: String, dnsId: UInt16,
                            questions: [[String: Any]] = []) {
        self.domain = domain
        self.queryType = queryType
        self.dnsId = dnsId
        self.questions = questions.isEmpty
            ? [["name": domain, "type": queryType, "class": "IN"]]
            : questions
    }

    public func recordResponse(responseCode: String, answers: [[String: Any]],
                               authorities: [[String: Any]], additionals: [[String: Any]]) {
        self.responseCode = responseCode
        self.answers = answers
        self.authorities = authorities
        self.additionals = additionals
        self.endedAt = Date().timeIntervalSince1970
    }

    public func buildFlowRecord(context: FlowBuildContext) -> FlowRecord {
        let firstAnswer = (answers.first?["data"] as? String) ?? ""
        let summaryAnswer = firstAnswer.isEmpty
            ? responseCode
            : firstAnswer

        var record = FlowRecord(
            flowId: flowId, protocolName: Self.protocolName,
            host: domain, port: serverPort, startedAt: startedAt
        )
        record.endedAt = endedAt
        if let ended = endedAt {
            record.durationMs = (ended - startedAt) * 1000
        }
        record.status = .completed
        record.summary = "\(queryType) \(domain) → \(summaryAnswer)"

        record.searchKey1 = queryType
        record.searchKey2 = domain
        record.searchKey3 = firstAnswer
        record.searchKey4 = responseCode

        var meta: [String: Any] = [
            "transport": transport.rawValue,
            "id": Int(dnsId),
            "questions": questions,
            "answers": answers,
            "authorities": authorities,
            "additionals": additionals
        ]
        if let httpId = httpFlowId {
            meta["httpFlowId"] = httpId
        }
        record.metadata = meta

        return record
    }
}
