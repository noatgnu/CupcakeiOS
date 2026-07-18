import CupcakeNetworking
import Foundation

public actor MetadataColumnTemplateSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?

    public init(apiClient: APIClient, deviceToken: @escaping @Sendable () -> String?) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
    }

    public func search(query: String, sourceSchema: String? = nil, limit: Int = 20) async throws -> [MetadataColumnTemplateDTO] {
        guard let token = deviceToken(), query.count >= 3 else { return [] }
        var queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let sourceSchema, !sourceSchema.isEmpty {
            queryItems.append(URLQueryItem(name: "source_schema", value: sourceSchema))
        }
        let page: PaginatedResponse<MetadataColumnTemplateDTO> = try await apiClient.get(
            "column-templates/",
            query: queryItems,
            authorizationHeader: "DeviceToken \(token)"
        )
        return page.results
    }

    public func searchGrouped(query: String, limit: Int = 20) async throws -> [GroupedColumnTemplateDTO] {
        guard let token = deviceToken(), query.count >= 3 else { return [] }
        let page: PaginatedResponse<GroupedColumnTemplateDTO> = try await apiClient.get(
            "column-templates/grouped_by_column/",
            query: [
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            authorizationHeader: "DeviceToken \(token)"
        )
        return page.results
    }

    public func myTemplates() async throws -> [MetadataColumnTemplateDTO] {
        guard let token = deviceToken() else { return [] }
        return try await apiClient.get("column-templates/my_templates/", authorizationHeader: "DeviceToken \(token)")
    }

    @discardableResult
    public func create(_ request: CreateColumnTemplateRequest) async throws -> MetadataColumnTemplateDTO {
        guard let token = deviceToken() else {
            throw MetadataColumnTemplateSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "column-templates/",
            method: .post,
            body: request,
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func update(templateServerID: Int64, request: CreateColumnTemplateRequest) async throws -> MetadataColumnTemplateDTO {
        guard let token = deviceToken() else {
            throw MetadataColumnTemplateSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "column-templates/\(templateServerID)/",
            method: .patch,
            body: request,
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    public func delete(templateServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw MetadataColumnTemplateSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "column-templates/\(templateServerID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
    }
}

public enum MetadataColumnTemplateSyncError: Error {
    case noDeviceToken
}
