import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

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
        try await apiClient.fetchAllPages(path: "metadata-table-templates/", authorizationHeader: "DeviceToken \(token)") { (dtos: [MetadataTableTemplateDTO]) in
            try await store.upsert(dtos)
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

    public func fetchDetail(templateServerID: Int64) async throws -> MetadataTableTemplateDTO {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let dto: MetadataTableTemplateDTO = try await apiClient.get(
            "metadata-table-templates/\(templateServerID)/",
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    @discardableResult
    public func duplicate(templateServerID: Int64) async throws -> MetadataTableTemplateDTO {
        let source = try await fetchDetail(templateServerID: templateServerID)
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let request = DuplicateMetadataTableTemplateRequest(
            name: "\(source.name) (Copy)",
            description: source.description,
            userColumnIds: (source.userColumns ?? []).map(\.id),
            visibility: "private",
            labGroup: nil
        )
        let dto: MetadataTableTemplateDTO = try await apiClient.send(
            "metadata-table-templates/",
            method: .post,
            body: request,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    @discardableResult
    public func addColumn(templateServerID: Int64, columnData: AddColumnDataRequest, autoReorder: Bool = false) async throws -> AddTemplateColumnResponse {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let path = autoReorder ? "metadata-table-templates/\(templateServerID)/add_column_with_auto_reorder/" : "metadata-table-templates/\(templateServerID)/add_column/"
        let response: AddTemplateColumnResponse = try await apiClient.send(
            path,
            method: .post,
            body: AddTemplateColumnRequest(columnData: columnData, autoReorder: autoReorder ? true : nil),
            authorizationHeader: "DeviceToken \(token)"
        )
        return response
    }

    public func removeColumn(templateServerID: Int64, columnServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let _: MessageResponse = try await apiClient.send(
            "metadata-table-templates/\(templateServerID)/remove_column/",
            method: .post,
            body: RemoveTemplateColumnRequest(columnId: columnServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    public func reorderColumn(templateServerID: Int64, columnServerID: Int64, newPosition: Int) async throws {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let _: MessageResponse = try await apiClient.send(
            "metadata-table-templates/\(templateServerID)/reorder_column/",
            method: .post,
            body: ReorderTemplateColumnRequest(columnId: columnServerID, newPosition: newPosition),
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func duplicateColumn(templateServerID: Int64, columnServerID: Int64, newName: String? = nil) async throws -> MetadataColumnDTO {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        let response: DuplicateTemplateColumnResponse = try await apiClient.send(
            "metadata-table-templates/\(templateServerID)/duplicate_column/",
            method: .post,
            body: DuplicateTemplateColumnRequest(columnId: columnServerID, newName: newName),
            authorizationHeader: "DeviceToken \(token)"
        )
        return response.column
    }

    @discardableResult
    public func syncFromSchemas(templateServerID: Int64, addNew: Bool = true, updateExisting: Bool = true, removeOrphans: Bool = false) async throws -> SyncTemplateFromSchemasResponse {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "metadata-table-templates/\(templateServerID)/sync_from_schemas/",
            method: .post,
            body: SyncTemplateFromSchemasRequest(addNew: addNew, updateExisting: updateExisting, removeOrphans: removeOrphans),
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func bulkDeleteColumns(templateServerID: Int64, columnServerIDs: [Int64]) async throws -> BulkDeleteTemplateColumnsResponse {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "metadata-table-templates/\(templateServerID)/bulk_delete_columns/",
            method: .post,
            body: BulkDeleteTemplateColumnsRequest(columnIds: columnServerIDs),
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func bulkUpdateStaffOnly(templateServerID: Int64, columnServerIDs: [Int64], staffOnly: Bool) async throws -> BulkUpdateStaffOnlyResponse {
        guard let token = deviceToken() else {
            throw MetadataTableTemplateSyncError.noDeviceToken
        }
        return try await apiClient.send(
            "metadata-table-templates/\(templateServerID)/bulk_update_staff_only/",
            method: .post,
            body: BulkUpdateStaffOnlyRequest(columnIds: columnServerIDs, staffOnly: staffOnly),
            authorizationHeader: "DeviceToken \(token)"
        )
    }
}

struct MessageResponse: Decodable, Sendable {
    let message: String
}

public enum MetadataTableTemplateSyncError: Error {
    case noDeviceToken
}

@ModelActor
actor MetadataTableTemplateStore {
    func upsert(_ dtos: [MetadataTableTemplateDTO]) throws {
        guard !dtos.isEmpty else { return }

        let templateServerIDs = Set(dtos.map(\.id))
        let existingTemplates = try modelContext.fetch(
            FetchDescriptor<CachedMetadataTableTemplate>(predicate: #Predicate { templateServerIDs.contains($0.serverID) })
        )
        var templatesByServerID = Dictionary(uniqueKeysWithValues: existingTemplates.map { ($0.serverID, $0) })

        for dto in dtos {
            let template: CachedMetadataTableTemplate
            if let found = templatesByServerID[dto.id] {
                template = found
            } else {
                let created = CachedMetadataTableTemplate(serverID: dto.id, name: dto.name, createdAt: Date.parsedISO8601(dto.createdAt))
                modelContext.insert(created)
                templatesByServerID[dto.id] = created
                template = created
            }
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
            template.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: template.updatedAt)
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
