import Foundation
import TunnelServices
import SQLite

/// ViewModel for WebSocket frame list with pagination
public class WebSocketDetailViewModel: ObservableObject {
    @Published public var frames: [DecodedEntry] = []
    @Published public var isLoading = false
    @Published public var hasMore = true

    private let flowId: String
    private let db: Connection
    private var pageIndex = 0
    private let pageSize = 50

    public init(flowId: String, db: Connection) {
        self.flowId = flowId
        self.db = db
    }

    public func loadFrames() {
        isLoading = true
        pageIndex = 0
        frames = (try? DecodedEntryDAO.findAll(db: db, flowId: flowId, offset: 0, limit: pageSize)) ?? []
        hasMore = frames.count >= pageSize
        isLoading = false
    }

    public func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        pageIndex += 1
        let more = (try? DecodedEntryDAO.findAll(db: db, flowId: flowId, offset: pageIndex * pageSize, limit: pageSize)) ?? []
        frames.append(contentsOf: more)
        hasMore = more.count >= pageSize
        isLoading = false
    }
}
