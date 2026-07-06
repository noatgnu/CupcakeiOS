import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Read-only, full-refetch population of lab groups — no offline-create path.
public actor LabGroupSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: LabGroupStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = LabGroupStore(modelContainer: modelContainer)
    }

    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<LabGroupDTO> = try await apiClient.get("lab-groups/my_groups/", authorizationHeader: authorization)
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }
}

@ModelActor
actor LabGroupStore {
    func upsert(_ dtos: [LabGroupDTO]) throws {
        for dto in dtos {
            let groupServerID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedLabGroup>(predicate: #Predicate { $0.serverID == groupServerID })
            )
            let group = existing?.first ?? {
                let created = CachedLabGroup(serverID: dto.id, name: dto.name, groupDescription: dto.description, allowProcessJobs: dto.allowProcessJobs)
                modelContext.insert(created)
                return created
            }()
            group.name = dto.name
            group.groupDescription = dto.description
            group.allowProcessJobs = dto.allowProcessJobs
        }
        try modelContext.save()
    }
}
