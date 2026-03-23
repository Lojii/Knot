import Foundation

public struct MapLocalRule {
    public var id: Int64 = 0
    public var enabled: Bool = true
    public var urlPattern: String = ""
    public var method: String? = nil
    public var statusCode: Int = 200
    public var responseHeaders: String = ""  // JSON string
    public var responseFile: String = ""
    public var comment: String = ""
    public var createdAt: Double = Date().timeIntervalSince1970

    public init() {}
    public init(id: Int64, enabled: Bool, urlPattern: String, method: String?,
                statusCode: Int, responseHeaders: String, responseFile: String,
                comment: String, createdAt: Double) {
        self.id = id; self.enabled = enabled; self.urlPattern = urlPattern
        self.method = method; self.statusCode = statusCode
        self.responseHeaders = responseHeaders; self.responseFile = responseFile
        self.comment = comment; self.createdAt = createdAt
    }
}

public struct MapRemoteRule {
    public var id: Int64 = 0
    public var enabled: Bool = true
    public var urlPattern: String = ""
    public var method: String? = nil
    public var replaceScheme: String? = nil
    public var replaceHost: String? = nil
    public var replacePort: Int? = nil
    public var replacePath: String? = nil
    public var comment: String = ""
    public var createdAt: Double = Date().timeIntervalSince1970

    public init() {}
    public init(id: Int64, enabled: Bool, urlPattern: String, method: String?,
                replaceScheme: String?, replaceHost: String?, replacePort: Int?,
                replacePath: String?, comment: String, createdAt: Double) {
        self.id = id; self.enabled = enabled; self.urlPattern = urlPattern
        self.method = method; self.replaceScheme = replaceScheme
        self.replaceHost = replaceHost; self.replacePort = replacePort
        self.replacePath = replacePath; self.comment = comment; self.createdAt = createdAt
    }
}

public struct BreakpointRule {
    public var id: Int64 = 0
    public var enabled: Bool = true
    public var urlPattern: String = ""
    public var method: String? = nil
    public var breakOn: String = "both"  // "request", "response", "both"
    public var comment: String = ""
    public var createdAt: Double = Date().timeIntervalSince1970

    public init() {}
    public init(id: Int64, enabled: Bool, urlPattern: String, method: String?,
                breakOn: String, comment: String, createdAt: Double) {
        self.id = id; self.enabled = enabled; self.urlPattern = urlPattern
        self.method = method; self.breakOn = breakOn
        self.comment = comment; self.createdAt = createdAt
    }
}
