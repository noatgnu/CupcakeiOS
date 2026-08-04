import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

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
        try await apiClient.fetchAllPages(path: "lab-groups/my_groups/", authorizationHeader: "DeviceToken \(token)") { (dtos: [LabGroupDTO]) in
            try await store.upsert(dtos)
        }
    }

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

    @discardableResult
    public func create(
        name: String,
        description: String?,
        parentGroupServerID: Int64?,
        allowMemberInvites: Bool,
        allowProcessJobs: Bool
    ) async throws -> LabGroupDTO {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        let dto: LabGroupDTO = try await apiClient.send(
            "lab-groups/",
            method: .post,
            body: CreateLabGroupRequest(
                name: name,
                description: description,
                parentGroup: parentGroupServerID,
                allowMemberInvites: allowMemberInvites,
                allowProcessJobs: allowProcessJobs
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    @discardableResult
    public func update(labGroupServerID: Int64, request: UpdateLabGroupRequest) async throws -> LabGroupDTO {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        let dto: LabGroupDTO = try await apiClient.send(
            "lab-groups/\(labGroupServerID)/",
            method: .patch,
            body: request,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    public func deleteGroup(labGroupServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("lab-groups/\(labGroupServerID)/", method: .delete, authorizationHeader: "DeviceToken \(token)")
        try await store.remove(serverID: labGroupServerID)
    }

    public func leaveGroup(labGroupServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("lab-groups/\(labGroupServerID)/leave/", method: .post, authorizationHeader: "DeviceToken \(token)")
        try await store.remove(serverID: labGroupServerID)
    }

    public func removeMember(labGroupServerID: Int64, userServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        let _: EmptyResponse = try await apiClient.send(
            "lab-groups/\(labGroupServerID)/remove_member/",
            method: .post,
            body: RemoveLabGroupMemberRequest(userID: userServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func inviteUser(labGroupServerID: Int64, email: String, message: String?) async throws -> LabGroupInvitationDTO {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "lab-groups/\(labGroupServerID)/invite_user/",
            method: .post,
            body: CreateLabGroupInvitationRequest(invitedEmail: email, message: message),
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    public func fetchMyPendingInvitations() async throws -> [LabGroupInvitationDTO] {
        guard let token = deviceToken() else { return [] }
        return try await apiClient.get("lab-group-invitations/my_pending_invitations/", authorizationHeader: "DeviceToken \(token)")
    }

    public func acceptInvitation(id: Int64) async throws {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("lab-group-invitations/\(id)/accept_invitation/", method: .post, authorizationHeader: "DeviceToken \(token)")
    }

    public func rejectInvitation(id: Int64) async throws {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("lab-group-invitations/\(id)/reject_invitation/", method: .post, authorizationHeader: "DeviceToken \(token)")
    }

    public func cancelInvitation(id: Int64) async throws {
        guard let token = deviceToken() else {
            throw LabGroupSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("lab-group-invitations/\(id)/cancel_invitation/", method: .post, authorizationHeader: "DeviceToken \(token)")
    }
}

public enum LabGroupSyncError: Error {
    case noDeviceToken
}

struct EmptyResponse: Decodable, Sendable {}

@ModelActor
actor LabGroupStore {
    func upsert(_ dtos: [LabGroupDTO]) throws {
        for dto in dtos {
            let groupServerID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedLabGroup>(predicate: #Predicate { $0.serverID == groupServerID })
            )
            let group = existing?.first ?? {
                let created = CachedLabGroup(
                    serverID: dto.id,
                    name: dto.name,
                    groupDescription: dto.description,
                    createdAt: Date.parsedISO8601(dto.createdAt)
                )
                modelContext.insert(created)
                return created
            }()
            group.name = dto.name
            group.groupDescription = dto.description
            group.parentGroupServerID = dto.parentGroup
            group.fullPathNames = dto.fullPath.map(\.name)
            group.creatorServerID = dto.creator
            group.creatorName = dto.creatorName
            group.isActive = dto.isActive
            group.allowMemberInvites = dto.allowMemberInvites
            group.allowProcessJobs = dto.allowProcessJobs
            group.memberCount = dto.memberCount
            group.subGroupsCount = dto.subGroupsCount
            group.isCreator = dto.isCreator
            group.isMember = dto.isMember
            group.canInvite = dto.canInvite
            group.canManage = dto.canManage
            group.canProcessJobs = dto.canProcessJobs
            group.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: group.updatedAt)
        }
        try modelContext.save()
    }

    func remove(serverID: Int64) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedLabGroup>(predicate: #Predicate { $0.serverID == serverID })
        )
        for group in existing {
            modelContext.delete(group)
        }
        try modelContext.save()
    }
}
