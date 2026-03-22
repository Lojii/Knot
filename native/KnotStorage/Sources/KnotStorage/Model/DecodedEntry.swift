import Foundation

/// A decoded payload entry.
/// Maps to the `decoded_entry` table in decoded.db.
public struct DecodedEntry {
    public let flowId: String
    public let direction: Int         // 0=request, 1=response
    public var originalEncoding: String
    public var decodedType: String
    public var decodedSize: Int64
    public var charset: String
    public var payloadRef: String
    public var isInline: Bool
    public var inlineData: Data?
    public var searchText: String?
    public var decodedAt: TimeInterval
    public var sequence: Int

    public init(flowId: String, direction: Int, originalEncoding: String = "",
                decodedType: String = "", decodedSize: Int64 = 0, charset: String = "utf-8",
                payloadRef: String = "", isInline: Bool = false, inlineData: Data? = nil,
                searchText: String? = nil, decodedAt: TimeInterval, sequence: Int = 0) {
        self.flowId = flowId
        self.direction = direction
        self.originalEncoding = originalEncoding
        self.decodedType = decodedType
        self.decodedSize = decodedSize
        self.charset = charset
        self.payloadRef = payloadRef
        self.isInline = isInline
        self.inlineData = inlineData
        self.searchText = searchText
        self.decodedAt = decodedAt
        self.sequence = sequence
    }
}

/// Result from PayloadDecoder
public struct DecodeResult {
    public let decodedSize: Int64
    public let searchText: String?
    public let detectedType: String
    public let payloadRef: String

    public init(decodedSize: Int64, searchText: String?, detectedType: String, payloadRef: String = "") {
        self.decodedSize = decodedSize
        self.searchText = searchText
        self.detectedType = detectedType
        self.payloadRef = payloadRef
    }
}

/// Combined decode result for a flow (request + response)
public struct DecodedPayload {
    public let request: DecodeResult?
    public let response: DecodeResult?

    public init(request: DecodeResult? = nil, response: DecodeResult? = nil) {
        self.request = request
        self.response = response
    }
}
