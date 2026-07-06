import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Online-only, like every other `InstrumentJob`-adjacent write path in this app — there's no
/// offline-authoring story for metadata tables (they only exist server-side, created from a
/// template). A `MetadataColumn` is always already server-backed by the time this app can reach
/// it (never locally created), so there's no `clientID`/outbox path to mirror here.
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
    public func updateColumnValue(columnServerID: Int64, value: String) async throws -> MetadataColumnDTO {
        guard let token = deviceToken() else {
            throw MetadataColumnSyncError.noDeviceToken
        }
        let response: UpdateColumnValueResponse = try await apiClient.send(
            "metadata-columns/\(columnServerID)/update_column_value/",
            method: .post,
            body: UpdateColumnValueRequest(value: value),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.updateSingle(response.column)
        return response.column
    }

    /// `search_type` is always `icontains` — this app's v1 slice doesn't expose the reference web
    /// app's "Contains"/"Starts with" toggle.
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
}

public enum MetadataColumnSyncError: Error {
    case noDeviceToken
}

@ModelActor
actor MetadataColumnStore {
    /// Updates the one column in place — unlike `InstrumentJobStore.upsertMetadataTable`'s
    /// delete-and-reinsert-all-columns strategy (appropriate for a full table refetch), a single
    /// value edit shouldn't discard and recreate every sibling column's local record.
    func updateSingle(_ dto: MetadataColumnDTO) throws {
        let columnServerID = dto.id
        guard let column = try modelContext.fetch(
            FetchDescriptor<CachedMetadataColumn>(predicate: #Predicate { $0.serverID == columnServerID })
        ).first else { return }
        column.value = dto.value
        column.notApplicable = dto.notApplicable
        column.notAvailable = dto.notAvailable
        try modelContext.save()
    }
}
