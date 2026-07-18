import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor AnnotationFolderSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: AnnotationFolderStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = AnnotationFolderStore(modelContainer: modelContainer)
    }

    public func fetchRootFolders(sessionServerID: Int64) async throws -> [AnnotationFolderDTO] {
        guard let token = deviceToken() else {
            return try await store.cachedRootFolders(sessionServerID: sessionServerID)
        }
        do {
            let authorization = "DeviceToken \(token)"
            let page: PaginatedResponse<SessionAnnotationFolderDTO> = try await apiClient.get(
                "session-annotation-folders/",
                query: [URLQueryItem(name: "session", value: String(sessionServerID))],
                authorizationHeader: authorization
            )
            var folders: [AnnotationFolderDTO] = []
            for junction in page.results {
                if let folder: AnnotationFolderDTO = try? await apiClient.get("annotation-folders/\(junction.folder)/", authorizationHeader: authorization) {
                    folders.append(folder)
                }
            }
            try await store.upsertRootFolders(sessionServerID: sessionServerID, folders: folders)
            return folders
        } catch let error as APIError {
            if case .transport = error {
                return try await store.cachedRootFolders(sessionServerID: sessionServerID)
            }
            throw error
        }
    }

    public func fetchChildren(folderServerID: Int64) async throws -> FolderChildrenResponse {
        guard let token = deviceToken() else {
            return try await store.cachedChildren(folderServerID: folderServerID)
        }
        do {
            let response: FolderChildrenResponse = try await apiClient.get(
                "annotation-folders/\(folderServerID)/children/",
                authorizationHeader: "DeviceToken \(token)"
            )
            try await store.upsertChildren(folderServerID: folderServerID, response: response)
            return response
        } catch let error as APIError {
            if case .transport = error {
                return try await store.cachedChildren(folderServerID: folderServerID)
            }
            throw error
        }
    }

    @discardableResult
    public func createRootFolder(sessionServerID: Int64, folderName: String) async throws -> AnnotationFolderDTO {
        guard let token = deviceToken() else {
            throw AnnotationFolderSyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"
        let folder: AnnotationFolderDTO = try await apiClient.send(
            "annotation-folders/",
            method: .post,
            body: CreateAnnotationFolderRequest(folderName: folderName),
            authorizationHeader: authorization
        )
        let _: SessionAnnotationFolderDTO = try await apiClient.send(
            "session-annotation-folders/",
            method: .post,
            body: AttachSessionAnnotationFolderRequest(session: sessionServerID, folder: folder.id),
            authorizationHeader: authorization
        )
        try await store.upsertRootFolders(sessionServerID: sessionServerID, folders: [folder])
        return folder
    }

    @discardableResult
    public func createSubfolder(parentFolderServerID: Int64, folderName: String) async throws -> AnnotationFolderDTO {
        guard let token = deviceToken() else {
            throw AnnotationFolderSyncError.noDeviceToken
        }
        let folder: AnnotationFolderDTO = try await apiClient.send(
            "annotation-folders/",
            method: .post,
            body: CreateAnnotationFolderRequest(folderName: folderName, parentFolder: parentFolderServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertFolder(folder, parentFolderServerID: parentFolderServerID)
        return folder
    }

    @discardableResult
    public func createTextAnnotation(folderServerID: Int64, text: String) async throws -> AnnotationSummaryDTO {
        guard let token = deviceToken() else {
            throw AnnotationFolderSyncError.noDeviceToken
        }
        let annotation: AnnotationSummaryDTO = try await apiClient.send(
            "annotations/",
            method: .post,
            body: CreateFolderAnnotationRequest(annotation: text, folder: folderServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertAnnotations(folderServerID: folderServerID, annotations: [annotation])
        return annotation
    }

    @discardableResult
    public func renameFolder(folderServerID: Int64, folderName: String) async throws -> AnnotationFolderDTO {
        guard let token = deviceToken() else {
            throw AnnotationFolderSyncError.noDeviceToken
        }
        let folder: AnnotationFolderDTO = try await apiClient.send(
            "annotation-folders/\(folderServerID)/",
            method: .patch,
            body: RenameAnnotationFolderRequest(folderName: folderName),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertFolder(folder, parentFolderServerID: folder.parentFolder)
        return folder
    }

    @discardableResult
    public func moveFolder(folderServerID: Int64, newParentServerID: Int64?) async throws -> AnnotationFolderDTO {
        guard let token = deviceToken() else {
            throw AnnotationFolderSyncError.noDeviceToken
        }
        let folder: AnnotationFolderDTO = try await apiClient.send(
            "annotation-folders/\(folderServerID)/",
            method: .patch,
            body: MoveAnnotationFolderRequest(parentFolder: newParentServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertFolder(folder, parentFolderServerID: newParentServerID)
        return folder
    }

    public func deleteFolder(folderServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw AnnotationFolderSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "annotation-folders/\(folderServerID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.deleteFolder(serverID: folderServerID)
    }
}

public enum AnnotationFolderSyncError: Error {
    case noDeviceToken
}

@ModelActor
actor AnnotationFolderStore {
    func upsertRootFolders(sessionServerID: Int64, folders: [AnnotationFolderDTO]) throws {
        for folder in folders {
            try upsertFolderRow(folder, parentFolderServerID: nil, sessionServerID: sessionServerID)
        }
        try modelContext.save()
    }

    func upsertChildren(folderServerID: Int64, response: FolderChildrenResponse) throws {
        for folder in response.folders {
            try upsertFolderRow(folder, parentFolderServerID: folderServerID, sessionServerID: nil)
        }
        try upsertAnnotationRows(folderServerID: folderServerID, annotations: response.annotations)
        try modelContext.save()
    }

    func upsertFolder(_ folder: AnnotationFolderDTO, parentFolderServerID: Int64?) throws {
        try upsertFolderRow(folder, parentFolderServerID: parentFolderServerID, sessionServerID: nil)
        try modelContext.save()
    }

    func upsertAnnotations(folderServerID: Int64, annotations: [AnnotationSummaryDTO]) throws {
        try upsertAnnotationRows(folderServerID: folderServerID, annotations: annotations)
        try modelContext.save()
    }

    func cachedRootFolders(sessionServerID: Int64) throws -> [AnnotationFolderDTO] {
        let cached = try modelContext.fetch(
            FetchDescriptor<CachedAnnotationFolder>(predicate: #Predicate { $0.sessionServerID == sessionServerID })
        )
        return cached.map(Self.dto(from:))
    }

    func cachedChildren(folderServerID: Int64) throws -> FolderChildrenResponse {
        let cachedFolders = try modelContext.fetch(
            FetchDescriptor<CachedAnnotationFolder>(predicate: #Predicate { $0.parentFolderServerID == folderServerID })
        )
        let cachedAnnotations = try modelContext.fetch(
            FetchDescriptor<CachedFolderAnnotation>(predicate: #Predicate { $0.folderServerID == folderServerID })
        )
        return FolderChildrenResponse(
            folders: cachedFolders.map(Self.dto(from:)),
            annotations: cachedAnnotations.map(Self.dto(from:))
        )
    }

    func deleteFolder(serverID: Int64) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedAnnotationFolder>(predicate: #Predicate { $0.serverID == serverID })
        )
        for folder in existing {
            modelContext.delete(folder)
        }
        try modelContext.save()
    }

    private func upsertFolderRow(_ dto: AnnotationFolderDTO, parentFolderServerID: Int64?, sessionServerID: Int64?) throws {
        let folderServerID = dto.id
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedAnnotationFolder>(predicate: #Predicate { $0.serverID == folderServerID })
        )
        let folder = existing.first ?? {
            let created = CachedAnnotationFolder(serverID: dto.id, folderName: dto.folderName)
            modelContext.insert(created)
            return created
        }()
        folder.folderName = dto.folderName
        folder.parentFolderServerID = parentFolderServerID ?? dto.parentFolder
        if let sessionServerID {
            folder.sessionServerID = sessionServerID
        }
        folder.childFoldersCount = dto.childFoldersCount ?? 0
        folder.annotationsCount = dto.annotationsCount ?? 0
        folder.canEdit = dto.canEdit
        folder.canDelete = dto.canDelete
    }

    private func upsertAnnotationRows(folderServerID: Int64, annotations: [AnnotationSummaryDTO]) throws {
        for dto in annotations {
            let annotationServerID = dto.id
            let existing = try modelContext.fetch(
                FetchDescriptor<CachedFolderAnnotation>(predicate: #Predicate { $0.serverID == annotationServerID })
            )
            let annotation = existing.first ?? {
                let created = CachedFolderAnnotation(serverID: dto.id, folderServerID: folderServerID, annotationText: dto.annotation)
                modelContext.insert(created)
                return created
            }()
            annotation.folderServerID = folderServerID
            annotation.annotationText = dto.annotation
            annotation.annotationType = dto.annotationType
            annotation.transcribed = dto.transcribed
            annotation.transcription = dto.transcription
            annotation.language = dto.language
            annotation.translation = dto.translation
        }
    }

    private static func dto(from folder: CachedAnnotationFolder) -> AnnotationFolderDTO {
        AnnotationFolderDTO(
            id: folder.serverID,
            folderName: folder.folderName,
            parentFolder: folder.parentFolderServerID,
            fullPath: nil,
            childFoldersCount: folder.childFoldersCount,
            annotationsCount: folder.annotationsCount,
            canEdit: folder.canEdit,
            canDelete: folder.canDelete
        )
    }

    private static func dto(from annotation: CachedFolderAnnotation) -> AnnotationSummaryDTO {
        AnnotationSummaryDTO(
            id: annotation.serverID,
            annotation: annotation.annotationText,
            annotationType: annotation.annotationType,
            folder: annotation.folderServerID,
            transcribed: annotation.transcribed,
            transcription: annotation.transcription,
            language: annotation.language,
            translation: annotation.translation
        )
    }
}
