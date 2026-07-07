import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Fetches, creates, updates, and deletes metadata table templates.
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

    @discardableResult
    public func createBlank(name: String, description: String?, labGroupServerID: Int64?) async throws -> MetadataTableTemplateDTO {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let dto: MetadataTableTemplateDTO = try await apiClient.send(
            "metadata-table-templates/",
            method: .post,
            body: CreateMetadataTableTemplateRequest(
                name: name,
                description: description,
                labGroup: labGroupServerID,
                visibility: labGroupServerID == nil ? "private" : "group"
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    @discardableResult
    public func createFromSchemas(name: String, schemaNames: [String], description: String?, labGroupServerID: Int64?) async throws -> MetadataTableTemplateDTO {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let dto: MetadataTableTemplateDTO = try await apiClient.send(
            "metadata-table-templates/create_from_schema/",
            method: .post,
            body: CreateMetadataTableTemplateFromSchemaRequest(
                name: name,
                schemas: schemaNames,
                description: description,
                labGroup: labGroupServerID
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    @discardableResult
    public func update(templateServerID: Int64, request: CreateMetadataTableTemplateRequest) async throws -> MetadataTableTemplateDTO {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let dto: MetadataTableTemplateDTO = try await apiClient.send(
            "metadata-table-templates/\(templateServerID)/",
            method: .patch,
            body: request,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    public func delete(templateServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "metadata-table-templates/\(templateServerID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.delete(serverID: templateServerID)
    }
}

public enum MetadataTableTemplateSyncError: Error {
    case noDeviceToken
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
            template.labGroupServerID = dto.labGroup
            template.canEdit = dto.canEdit
            template.canDelete = dto.canDelete
            template.schemaNames = dto.schemaNames
        }
        try modelContext.save()
    }

    func delete(serverID: Int64) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedMetadataTableTemplate>(predicate: #Predicate { $0.serverID == serverID })
        )
        for template in existing {
            modelContext.delete(template)
        }
        try modelContext.save()
    }
}
