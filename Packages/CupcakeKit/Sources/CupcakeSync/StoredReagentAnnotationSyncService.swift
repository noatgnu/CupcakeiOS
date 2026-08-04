import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor StoredReagentAnnotationSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: StoredReagentAnnotationStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = StoredReagentAnnotationStore(modelContainer: modelContainer)
    }

    public func fetchDocumentFolders() async throws -> [AnnotationFolderDTO] {
        guard let token = deviceToken() else { return [] }
        let page: PaginatedResponse<AnnotationFolderDTO> = try await apiClient.get(
            "annotation-folders/",
            query: [URLQueryItem(name: "resource_type", value: "file")],
            authorizationHeader: "DeviceToken \(token)"
        )
        return page.results.filter { ["MSDS", "Certificates", "Manuals"].contains($0.folderName) }
    }

    public func refetch(storedReagentServerID: Int64) async throws {
        guard let token = deviceToken() else { return }
        try await apiClient.fetchAllPages(
            path: "stored-reagent-annotations/",
            query: [URLQueryItem(name: "stored_reagent", value: String(storedReagentServerID))],
            authorizationHeader: "DeviceToken \(token)"
        ) { (dtos: [StoredReagentAnnotationDTO]) in
            try await store.upsert(dtos)
        }
    }

    @discardableResult
    public func create(storedReagentServerID: Int64, folderServerID: Int64, text: String) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw StoredReagentAnnotationSyncError.noDeviceToken
        }
        let dto: StoredReagentAnnotationDTO = try await apiClient.send(
            "stored-reagent-annotations/",
            method: .post,
            body: CreateStoredReagentAnnotationRequest(storedReagent: storedReagentServerID, folder: folderServerID, annotationType: "text", annotation: text),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto.id
    }

    public func delete(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw StoredReagentAnnotationSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("stored-reagent-annotations/\(serverID)/", method: .delete, authorizationHeader: "DeviceToken \(token)")
        try await store.removeLocal(serverID: serverID)
    }
}

public enum StoredReagentAnnotationSyncError: Error {
    case noDeviceToken
}

actor StoredReagentAnnotationStore {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func upsert(_ dtos: [StoredReagentAnnotationDTO]) throws {
        for dto in dtos {
            try upsertSingle(dto)
        }
    }

    func upsertSingle(_ dto: StoredReagentAnnotationDTO) throws {
        let serverID = dto.id
        if let existing = try modelContext.fetch(FetchDescriptor<CachedStoredReagentAnnotation>(predicate: #Predicate { $0.serverID == serverID })).first {
            existing.storedReagentServerID = dto.storedReagent
            existing.folderServerID = dto.folder
            existing.folderName = dto.folderName ?? existing.folderName
            existing.annotationText = dto.annotationText
            existing.annotationType = dto.annotationType
            existing.scratched = dto.scratched
        } else {
            modelContext.insert(CachedStoredReagentAnnotation(
                serverID: dto.id,
                storedReagentServerID: dto.storedReagent,
                folderServerID: dto.folder,
                folderName: dto.folderName ?? "",
                annotationText: dto.annotationText,
                annotationType: dto.annotationType,
                scratched: dto.scratched
            ))
        }
        try modelContext.save()
    }

    func removeLocal(serverID: Int64) throws {
        guard let existing = try modelContext.fetch(FetchDescriptor<CachedStoredReagentAnnotation>(predicate: #Predicate { $0.serverID == serverID })).first else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }
}
