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

    /// `direct_only=true`, since staff assignment requires direct membership server-side. Only the first page.
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

    /// Every `LabGroupPermission` grant recorded for this lab group.
    public func fetchPermissions(labGroupServerID: Int64) async throws -> [LabGroupPermissionDTO] {
        guard let token = deviceToken() else { return [] }
        let authorization = "DeviceToken \(token)"
        let page: PaginatedResponse<LabGroupPermissionDTO> = try await apiClient.get(
            "lab-group-permissions/",
            query: [URLQueryItem(name: "lab_group", value: String(labGroupServerID))],
            authorizationHeader: authorization
        )
        return page.results
    }

    /// Check-then-PATCH-or-POST, since a blind POST risks a duplicate-key crash for an existing grant.
    @discardableResult
    public func setPermission(
        userServerID: Int64,
        labGroupServerID: Int64,
        canView: Bool,
        canInvite: Bool,
        canManage: Bool,
        canProcessJobs: Bool
    ) async throws -> LabGroupPermissionDTO {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"

        let existing: PaginatedResponse<LabGroupPermissionDTO> = try await apiClient.get(
            "lab-group-permissions/",
            query: [
                URLQueryItem(name: "lab_group", value: String(labGroupServerID)),
                URLQueryItem(name: "user", value: String(userServerID)),
            ],
            authorizationHeader: authorization
        )

        if let existingPermission = existing.results.first {
            return try await apiClient.send(
                "lab-group-permissions/\(existingPermission.id)/",
                method: .patch,
                body: UpdateLabGroupPermissionRequest(canView: canView, canInvite: canInvite, canManage: canManage, canProcessJobs: canProcessJobs),
                authorizationHeader: authorization
            )
        } else {
            return try await apiClient.send(
                "lab-group-permissions/",
                method: .post,
                body: CreateLabGroupPermissionRequest(user: userServerID, labGroup: labGroupServerID, canView: canView, canInvite: canInvite, canManage: canManage, canProcessJobs: canProcessJobs),
                authorizationHeader: authorization
            )
        }
    }
}

public enum LabGroupSyncError: Error {
    case noDeviceToken
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
