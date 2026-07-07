import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Online-only. A `MetadataColumn` is always already server-backed, never locally created.
public actor MetadataColumnSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: MetadataColumnStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = MetadataColumnStore(modelContainer: modelContainer)
    }

    @discardableResult
    public func updateColumnValue(
        columnServerID: Int64,
        value: String,
        sampleIndices: [Int]? = nil,
        valueType: ColumnValueUpdateType = .default
    ) async throws -> MetadataColumnDTO {
        guard let token = deviceToken() else {
            throw MetadataColumnSyncError.noDeviceToken
        }
        let response: UpdateColumnValueResponse = try await apiClient.send(
            "metadata-columns/\(columnServerID)/update_column_value/",
            method: .post,
            body: UpdateColumnValueRequest(value: value, sampleIndices: sampleIndices, valueType: valueType),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.updateSingle(response.column)
        return response.column
    }

    /// `search_type` is always `icontains`.
    public func fetchOntologySuggestions(columnServerID: Int64, search: String, limit: Int = 10) async throws -> [OntologySuggestionDTO] {
        guard let token = deviceToken(), search.count >= 2 else { return [] }
        let authorization = "DeviceToken \(token)"
        let response: OntologySuggestionsResponse = try await apiClient.get(
            "metadata-columns/ontology_suggestions/",
            query: [
                URLQueryItem(name: "column_id", value: String(columnServerID)),
                URLQueryItem(name: "search", value: search),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "search_type", value: "icontains"),
            ],
            authorizationHeader: authorization
        )
        return response.suggestions
    }

    public func fetchOntologySuggestions(ontologyType: String, customFilters: [String: [String: String]]?, search: String, limit: Int = 10) async throws -> [OntologySuggestionDTO] {
        guard let token = deviceToken(), search.count >= 2 else { return [] }
        let authorization = "DeviceToken \(token)"
        var query = [
            URLQueryItem(name: "q", value: search),
            URLQueryItem(name: "type", value: ontologyType),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "match", value: "contains"),
        ]
        if let customFilters, let data = try? JSONEncoder().encode(customFilters), let json = String(data: data, encoding: .utf8) {
            query.append(URLQueryItem(name: "custom_filters", value: json))
        }
        let response: OntologySuggestionsResponse = try await apiClient.get(
            "ontology/search/suggest/",
            query: query,
            authorizationHeader: authorization
        )
        return response.suggestions
    }

    @discardableResult
    public func addColumn(tableServerID: Int64, columnData: AddColumnDataRequest) async throws -> MetadataColumnDTO {
        guard let token = deviceToken() else {
            throw MetadataColumnSyncError.noDeviceToken
        }
        let response: AddColumnWithAutoReorderResponse = try await apiClient.send(
            "metadata-tables/\(tableServerID)/add_column_with_auto_reorder/",
            method: .post,
            body: AddColumnWithAutoReorderRequest(columnData: columnData),
            authorizationHeader: "DeviceToken \(token)"
        )
        return response.column
    }

    public func removeColumn(tableServerID: Int64, columnServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw MetadataColumnSyncError.noDeviceToken
        }
        let _: RemoveColumnResponse = try await apiClient.send(
            "metadata-tables/\(tableServerID)/remove_column/",
            method: .post,
            body: RemoveColumnRequest(columnId: columnServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
    }
}

public enum MetadataColumnSyncError: Error {
    case noDeviceToken
}

@ModelActor
actor MetadataColumnStore {
    /// Updates the one column in place, without discarding sibling columns' local records.
    func updateSingle(_ dto: MetadataColumnDTO) throws {
        let columnServerID = dto.id
        guard let column = try modelContext.fetch(
            FetchDescriptor<CachedMetadataColumn>(predicate: #Predicate { $0.serverID == columnServerID })
        ).first else { return }
        column.value = dto.value
        column.notApplicable = dto.notApplicable
        column.notAvailable = dto.notAvailable
        column.modifiers = dto.modifiers.map { MetadataColumnModifier(samples: $0.samples, value: $0.value) }
        try modelContext.save()
    }
}
