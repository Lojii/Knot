import Foundation
import SwiftUI
import TunnelServices
import SQLite

/// ViewModel for the unified Flow list
public class FlowListViewModel: ObservableObject {
    @Published public var flows: [FlowRecord] = []
    @Published public var protocolCounts: [String: Int] = [:]
    @Published public var isLoading = false
    @Published public var hasMore = true

    public var protocolFilter: String?
    public var keyword: String?

    private let dbGroup: TaskDatabaseGroup
    private var pageIndex: Int = 0
    private let pageSize: Int = 50

    public init(dbGroup: TaskDatabaseGroup) {
        self.dbGroup = dbGroup
    }

    public func loadFlows() {
        isLoading = true
        pageIndex = 0

        let results = (try? FlowDAO.query(
            db: dbGroup.proto,
            protocolFilter: protocolFilter,
            keyword: keyword,
            offset: 0,
            limit: pageSize
        )) ?? []

        flows = results
        hasMore = results.count >= pageSize
        isLoading = false

        loadCounts()
    }

    public func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        pageIndex += 1

        let results = (try? FlowDAO.query(
            db: dbGroup.proto,
            protocolFilter: protocolFilter,
            keyword: keyword,
            offset: pageIndex * pageSize,
            limit: pageSize
        )) ?? []

        flows.append(contentsOf: results)
        hasMore = results.count >= pageSize
        isLoading = false
    }

    public func refresh() {
        loadFlows()
    }

    private func loadCounts() {
        protocolCounts = (try? FlowDAO.countByProtocol(db: dbGroup.proto)) ?? [:]
    }
}
