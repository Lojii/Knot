import SwiftUI
import TunnelServices

/// Routes to the appropriate detail view based on protocol type
public struct FlowDetailRouter: View {
    let flow: FlowRecord
    let dbGroup: TaskDatabaseGroup

    public init(flow: FlowRecord, dbGroup: TaskDatabaseGroup) {
        self.flow = flow
        self.dbGroup = dbGroup
    }

    public var body: some View {
        switch flow.protocolName {
        case "HTTP", "HTTPS", "H2", "H3":
            HTTPDetailView(flow: flow, dbGroup: dbGroup)
        case "WS", "WSS":
            WebSocketDetailView(flow: flow, dbGroup: dbGroup)
        case "DNS":
            DNSDetailView(flow: flow)
        case "gRPC":
            GRPCDetailView(flow: flow, dbGroup: dbGroup)
        default:
            GenericFlowDetailView(flow: flow)
        }
    }
}
