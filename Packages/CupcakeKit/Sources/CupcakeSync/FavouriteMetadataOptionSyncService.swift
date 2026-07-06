import CupcakeNetworking
import Foundation

public actor FavouriteMetadataOptionSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?

    public init(apiClient: APIClient, deviceToken: @escaping @Sendable () -> String?) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
    }

    public func fetchPersonalFavourites(columnName: String? = nil, userID: Int64, limit: Int = 10) async throws -> [FavouriteMetadataOptionDTO] {
        try await fetch(columnName: columnName, query: [URLQueryItem(name: "user_id", value: String(userID))], limit: limit)
    }

    public func fetchLabGroupFavourites(columnName: String? = nil, labGroupID: Int64, limit: Int = 10) async throws -> [FavouriteMetadataOptionDTO] {
        try await fetch(columnName: columnName, query: [URLQueryItem(name: "lab_group_id", value: String(labGroupID))], limit: limit)
    }

    public func fetchGlobalFavourites(columnName: String? = nil, limit: Int = 10) async throws -> [FavouriteMetadataOptionDTO] {
        try await fetch(columnName: columnName, query: [URLQueryItem(name: "is_global", value: "true")], limit: limit)
    }

    private func fetch(columnName: String?, query: [URLQueryItem], limit: Int) async throws -> [FavouriteMetadataOptionDTO] {
        guard let token = deviceToken() else { return [] }
        var fullQuery = query + [URLQueryItem(name: "limit", value: String(limit))]
        if let columnName {
            fullQuery.append(URLQueryItem(name: "name", value: columnName))
        }
        let page: PaginatedResponse<FavouriteMetadataOptionDTO> = try await apiClient.get(
            "favourite-options/",
            query: fullQuery,
            authorizationHeader: "DeviceToken \(token)"
        )
        return page.results
    }

    @discardableResult
    public func createFavourite(_ request: CreateFavouriteMetadataOptionRequest) async throws -> FavouriteMetadataOptionDTO {
        guard let token = deviceToken() else {
            throw FavouriteMetadataOptionSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "favourite-options/",
            method: .post,
            body: request,
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    public func deleteFavourite(id: Int64) async throws {
        guard let token = deviceToken() else {
            throw FavouriteMetadataOptionSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "favourite-options/\(id)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
    }
}

public enum FavouriteMetadataOptionSyncError: Error {
    case noDeviceToken
}
