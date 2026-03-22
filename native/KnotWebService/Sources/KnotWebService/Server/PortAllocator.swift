import NIOCore
import NIOPosix

public enum PortAllocationError: Error, CustomStringConvertible {
    case exhausted(preferredPort: Int, maxRetries: Int)

    public var description: String {
        switch self {
        case .exhausted(let p, let n):
            return "Could not bind port \(p)-\(p + n - 1)"
        }
    }
}

enum PortAllocator {
    static func bindWithRetry(
        bootstrap: ServerBootstrap,
        host: String,
        preferredPort: Int,
        maxRetries: Int
    ) throws -> Channel {
        for offset in 0..<maxRetries {
            let port = preferredPort + offset
            if let ch = try? bootstrap.bind(host: host, port: port).wait() {
                return ch
            }
        }
        throw PortAllocationError.exhausted(preferredPort: preferredPort, maxRetries: maxRetries)
    }
}
