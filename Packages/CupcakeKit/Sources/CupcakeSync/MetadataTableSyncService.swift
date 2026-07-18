import CupcakeNetworking
import Foundation

public actor MetadataTableSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?

    public init(apiClient: APIClient, deviceToken: @escaping @Sendable () -> String?) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
    }

    public struct SearchFilters: Sendable {
        public var search: String = ""
        public var labGroupServerID: Int64?
        public var isPublished: Bool?
        public var isLocked: Bool?
        public var showShared: Bool = false
        public var adminView: Bool = false
        public var columnName: String = ""
        public var columnValue: String = ""
        public var columnType: String = ""
        public var exactColumnMatch: Bool = false

        public init() {}
    }

    public func search(filters: SearchFilters, limit: Int = 25, offset: Int = 0) async throws -> (count: Int, results: [MetadataTableDTO]) {
        guard let token = deviceToken() else { return (0, []) }
        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if !filters.search.isEmpty { query.append(URLQueryItem(name: "search", value: filters.search)) }
        if let labGroupServerID = filters.labGroupServerID {
            query.append(URLQueryItem(name: "lab_group_id", value: String(labGroupServerID)))
        }
        if let isPublished = filters.isPublished {
            query.append(URLQueryItem(name: "is_published", value: isPublished ? "true" : "false"))
        }
        if let isLocked = filters.isLocked {
            query.append(URLQueryItem(name: "is_locked", value: isLocked ? "true" : "false"))
        }
        if filters.showShared { query.append(URLQueryItem(name: "show_shared", value: "true")) }
        if filters.adminView { query.append(URLQueryItem(name: "admin_view", value: "true")) }
        if !filters.columnName.isEmpty { query.append(URLQueryItem(name: "column_name", value: filters.columnName)) }
        if !filters.columnValue.isEmpty { query.append(URLQueryItem(name: "column_value", value: filters.columnValue)) }
        if !filters.columnType.isEmpty { query.append(URLQueryItem(name: "column_type", value: filters.columnType)) }
        if !filters.columnName.isEmpty || !filters.columnValue.isEmpty || !filters.columnType.isEmpty {
            query.append(URLQueryItem(name: "column_match", value: filters.exactColumnMatch ? "exact" : "contains"))
        }
        let page: PaginatedResponse<MetadataTableDTO> = try await apiClient.get(
            "metadata-tables/",
            query: query,
            authorizationHeader: "DeviceToken \(token)"
        )
        return (page.count, page.results)
    }

    public func fetchDetail(tableServerID: Int64) async throws -> MetadataTableDTO {
        guard let token = deviceToken() else {
            throw MetadataTableSyncError.noDeviceToken
        }
        return try await apiClient.get(
            "metadata-tables/\(tableServerID)/",
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func update(tableServerID: Int64, request: UpdateMetadataTableRequest) async throws -> MetadataTableDTO {
        guard let token = deviceToken() else {
            throw MetadataTableSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "metadata-tables/\(tableServerID)/",
            method: .patch,
            body: request,
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    public func delete(tableServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw MetadataTableSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "metadata-tables/\(tableServerID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func advancedAutofill(tableServerID: Int64, request: AdvancedAutofillRequest) async throws -> AdvancedAutofillResponse {
        guard let token = deviceToken() else {
            throw MetadataTableSyncError.noDeviceToken
        }
        return try await apiClient.sendRawJSON(
            "metadata-tables/\(tableServerID)/advanced_autofill/",
            method: .post,
            json: request.rawJSON,
            authorizationHeader: "DeviceToken \(token)"
        )
    }
}

public enum MetadataTableSyncError: Error {
    case noDeviceToken
}
