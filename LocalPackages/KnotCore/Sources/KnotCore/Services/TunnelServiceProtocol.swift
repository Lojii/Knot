import Foundation
import Observation

@Observable
public final class TunnelServiceState {
    public var status: TunnelStatus = .disconnected
    public init() {}
}

public struct CaptureConfig: Sendable {
    public var localPort: Int
    public var localEnabled: Bool
    public var wifiPort: Int
    public var wifiEnabled: Bool
    public var ruleId: String?

    public init(
        localPort: Int = 8034, localEnabled: Bool = true,
        wifiPort: Int = 8034, wifiEnabled: Bool = false,
        ruleId: String? = nil
    ) {
        self.localPort = localPort; self.localEnabled = localEnabled
        self.wifiPort = wifiPort; self.wifiEnabled = wifiEnabled
        self.ruleId = ruleId
    }
}

public protocol TunnelServiceProtocol: AnyObject {
    var state: TunnelServiceState { get }
    func startCapture(config: CaptureConfig) async throws
    func stopCapture() async throws
    func installExtension() async throws
    func uninstallExtension() async throws
}
