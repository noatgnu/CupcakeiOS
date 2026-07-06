import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Read-only, full-refetch population of metadata table templates — the backend's own queryset
/// already scopes results to what this user can see (owned + public + accessible-group), so a
/// plain full-refetch needs no further client-side filtering.
public actor MetadataTableTemplateSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: MetadataTableTemplateStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = MetadataTableTemplateStore(modelContainer: modelContainer)
    }

    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<MetadataTableTemplateDTO> = try await apiClient.get("metadata-table-templates/", authorizationHeader: authorization)
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }
}

@ModelActor
actor MetadataTableTemplateStore {
    func upsert(_ dtos: [MetadataTableTemplateDTO]) throws {
        for dto in dtos {
            let templateServerID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedMetadataTableTemplate>(predicate: #Predicate { $0.serverID == templateServerID })
            )
            let template = existing?.first ?? {
                let created = CachedMetadataTableTemplate(serverID: dto.id, name: dto.name)
                modelContext.insert(created)
                return created
            }()
            template.name = dto.name
            template.templateDescription = dto.description
            template.ownerUsername = dto.ownerUsername
            template.visibility = dto.visibility
            template.isDefault = dto.isDefault
            template.columnCount = dto.columnCount
        }
        try modelContext.save()
    }
}
