import Foundation

/// Direction of payload data
public enum PayloadDirection {
    case request
    case response

    var suffix: String {
        switch self {
        case .request: return "req"
        case .response: return "rsp"
        }
    }
}

/// Centralized path computation for all storage files.
/// All file paths must go through this enum — no other module should construct paths directly.
public enum PathManager {

    /// App Group root directory (production default)
    public static var root: String {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.Lojii.NIO1901")!
            .path
    }

    // MARK: - Global

    public static func catalogDBPath(root: String? = nil) -> String {
        "\(root ?? self.root)/catalog.db"
    }

    public static func certDirectory(root: String? = nil) -> String {
        "\(root ?? self.root)/Cert"
    }

    // MARK: - Task Level

    public static func taskDirectory(_ taskId: Int64, root: String? = nil) -> String {
        "\(root ?? self.root)/tasks/\(taskId)"
    }

    public static func transportDBPath(_ taskId: Int64, root: String? = nil) -> String {
        "\(taskDirectory(taskId, root: root))/transport.db"
    }

    public static func protocolDBPath(_ taskId: Int64, root: String? = nil) -> String {
        "\(taskDirectory(taskId, root: root))/protocol.db"
    }

    public static func decodedDBPath(_ taskId: Int64, root: String? = nil) -> String {
        "\(taskDirectory(taskId, root: root))/decoded.db"
    }

    public static func stateDBPath(_ taskId: Int64, root: String? = nil) -> String {
        "\(taskDirectory(taskId, root: root))/state.db"
    }

    // MARK: - Payloads

    public static func payloadsDirectory(_ taskId: Int64, root: String? = nil) -> String {
        "\(taskDirectory(taskId, root: root))/payloads"
    }

    public static func rawPayloadPath(taskId: Int64, ref: String, root: String? = nil) -> String {
        "\(payloadsDirectory(taskId, root: root))/raw/\(ref)"
    }

    public static func decodedPayloadPath(taskId: Int64, flowId: String, direction: PayloadDirection, ext: String = "bin", root: String? = nil) -> String {
        "\(payloadsDirectory(taskId, root: root))/decoded/\(flowId)_\(direction.suffix).\(ext)"
    }

    public static func modifiedPayloadPath(taskId: Int64, flowId: String, version: Int, direction: PayloadDirection, root: String? = nil) -> String {
        "\(payloadsDirectory(taskId, root: root))/modified/\(flowId)_v\(version)_\(direction.suffix).bin"
    }

    // MARK: - Directory Creation

    public static func ensureTaskDirectories(_ taskId: Int64, root: String? = nil) throws {
        let r = root ?? self.root
        let dirs = [
            taskDirectory(taskId, root: r),
            "\(payloadsDirectory(taskId, root: r))/raw",
            "\(payloadsDirectory(taskId, root: r))/decoded",
            "\(payloadsDirectory(taskId, root: r))/modified",
            "\(taskDirectory(taskId, root: r))/export",
        ]
        for dir in dirs {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true
            )
        }
    }
}
