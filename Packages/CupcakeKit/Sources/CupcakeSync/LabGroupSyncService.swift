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

    /// `direct_only=true` — matches the reference web app's own `getLabGroupMembers` call for
    /// job-submission staff candidates (`job-submission-state.ts`): direct membership only, not
    /// bubbled-up sub-group members, since staff assignment itself requires direct membership
    /// server-side (`InstrumentJobSerializer.validate` rule 2). Only the first page — matching
    /// the reference app's own `limit: 10` for this exact picker, not a general limitation.
    public func fetchMembers(labGroupServerID: Int64) async throws -> [UserDTO] {
        guard let token = deviceToken() else { return [] }
        let authorization = "DeviceToken \(token)"
        let page: PaginatedResponse<UserDTO> = try await apiClient.get(
            "lab-groups/\(labGroupServerID)/members/",
            query: [URLQueryItem(name: "direct_only", value: "true")],
            authorizationHeader: authorization
        )
        return page.results
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
