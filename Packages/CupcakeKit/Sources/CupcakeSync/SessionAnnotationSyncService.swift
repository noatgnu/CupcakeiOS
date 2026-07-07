import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Fetches, creates, and syncs session-level annotations.
public actor SessionAnnotationSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: SessionAnnotationStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = SessionAnnotationStore(modelContainer: modelContainer)
    }

    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<SessionAnnotationDTO> = try await apiClient.get(
            "session-annotations/",
            authorizationHeader: authorization
        )
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    /// Persists the recorded file locally and inserts a local record, with no network call.
    @discardableResult
    public func createAudioAnnotation(
        sessionClientID: UUID,
        recordedFileURL: URL,
        transcription: String?,
        language: String?,
        translation: String?
    ) async throws -> UUID {
        try await createFileAnnotation(
            sessionClientID: sessionClientID,
            fileURL: recordedFileURL,
            fileExtension: "m4a",
            annotationType: "audio",
            transcription: transcription,
            language: language,
            translation: translation
        )
    }

    /// Persists a photo's JPEG data locally and inserts a local record, with no network call.
    @discardableResult
    public func createImageAnnotation(sessionClientID: UUID, imageData: Data) async throws -> UUID {
        let clientID = UUID()
        let fileName = try PendingAnnotationFileStorage.persist(imageData, clientID: clientID, fileExtension: "jpg")
        return try await store.insertLocalFileOnly(
            clientID: clientID,
            sessionClientID: sessionClientID,
            annotationType: "image",
            pendingFileName: fileName
        )
    }

    /// Persists a video's file data locally and inserts a local record, with no network call.
    @discardableResult
    public func createVideoAnnotation(
        sessionClientID: UUID,
        videoData: Data,
        fileExtension: String,
        transcription: String? = nil,
        language: String? = nil,
        translation: String? = nil
    ) async throws -> UUID {
        let clientID = UUID()
        let fileName = try PendingAnnotationFileStorage.persist(videoData, clientID: clientID, fileExtension: fileExtension)
        return try await store.insertLocalFileOnly(
            clientID: clientID,
            sessionClientID: sessionClientID,
            annotationType: "video",
            transcription: transcription,
            language: language,
            translation: translation,
            pendingFileName: fileName
        )
    }

    /// Persists a sketch's JSON vector data locally and inserts a local record, with no network call.
    @discardableResult
    public func createSketchAnnotation(sessionClientID: UUID, sketchData: Data) async throws -> UUID {
        let clientID = UUID()
        let fileName = try PendingAnnotationFileStorage.persist(sketchData, clientID: clientID, fileExtension: "json")
        return try await store.insertLocalFileOnly(
            clientID: clientID,
            sessionClientID: sessionClientID,
            annotationType: "sketch",
            pendingFileName: fileName
        )
    }

    /// Persists any not-yet-synced file annotation (audio, photo, video) locally with no network call.
    @discardableResult
    public func createFileAnnotation(
        sessionClientID: UUID,
        fileURL: URL,
        fileExtension: String,
        annotationType: String,
        transcription: String? = nil,
        language: String? = nil,
        translation: String? = nil
    ) async throws -> UUID {
        let clientID = UUID()
        let fileName = try PendingAnnotationFileStorage.persist(fileURL, clientID: clientID, fileExtension: fileExtension)
        return try await store.insertLocalFileOnly(
            clientID: clientID,
            sessionClientID: sessionClientID,
            annotationType: annotationType,
            transcription: transcription,
            language: language,
            translation: translation,
            pendingFileName: fileName
        )
    }

    /// Pushes an already locally-created audio annotation to the server.
    @discardableResult
    public func syncLocallyCreatedAudioAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedFileAnnotation(clientID: clientID)
    }

    /// Pushes an already locally-created photo annotation to the server.
    @discardableResult
    public func syncLocallyCreatedImageAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedFileAnnotation(clientID: clientID)
    }

    /// Pushes an already locally-created video annotation to the server.
    @discardableResult
    public func syncLocallyCreatedVideoAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedFileAnnotation(clientID: clientID)
    }

    /// Pushes an already locally-created sketch annotation to the server.
    @discardableResult
    public func syncLocallyCreatedSketchAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedFileAnnotation(clientID: clientID)
    }

    /// Pushes any not-yet-synced file annotation, deriving its MIME type from the annotation type and file extension.
    @discardableResult
    public func syncLocallyCreatedFileAnnotation(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw SessionAnnotationSyncError.noDeviceToken
        }
        let fields = try await store.fileAnnotationFields(clientID: clientID)
        guard let sessionServerID = fields.sessionServerID else {
            throw SyncDependencyError.parentNotSynced
        }
        let authorization = "DeviceToken \(token)"
        let fileURL = PendingAnnotationFileStorage.url(forFileName: fields.pendingFileName)
        let fileData = try Data(contentsOf: fileURL)
        let checksum = SHA256Checksum.hexDigest(of: fileData)
        let mimeType = AnnotationMimeType.mimeType(annotationType: fields.annotationType, fileExtension: fileURL.pathExtension)

        var form = MultipartFormBuilder()
        form.addField(name: "session_id", value: String(sessionServerID))
        form.addField(name: "annotation_type", value: fields.annotationType)
        form.addField(name: "auto_transcribe", value: fields.transcription == nil && ["audio", "video"].contains(fields.annotationType) ? "true" : "false")
        form.addField(name: "sha256", value: checksum)
        form.addField(name: "filename", value: fileURL.lastPathComponent)
        form.addFile(name: "file", filename: fileURL.lastPathComponent, mimeType: mimeType, data: fileData)

        let response: AnnotationChunkedUploadResponse = try await apiClient.sendMultipart(
            "upload/session-annotation-chunks/",
            body: form,
            authorizationHeader: authorization
        )
        if let warning = response.warning {
            throw SessionAnnotationSyncError.uploadFailed(warning)
        }
        guard let sessionAnnotationID = response.sessionAnnotationId else {
            throw SessionAnnotationSyncError.uploadFailed(response.message ?? "Upload did not return a session annotation id")
        }

        if fields.transcription != nil || fields.translation != nil {
            let _: SessionAnnotationDTO = try await apiClient.send(
                "session-annotations/\(sessionAnnotationID)/",
                method: .patch,
                body: UpdateSessionAnnotationTranscriptionRequest(transcription: fields.transcription, language: fields.language, translation: fields.translation),
                authorizationHeader: authorization
            )
        }

        PendingAnnotationFileStorage.remove(fileName: fields.pendingFileName)
        try await store.attachFileServerID(clientID: clientID, serverID: sessionAnnotationID)
        return sessionAnnotationID
    }

    /// Fetches a fresh copy of an already-synced annotation, for a live, unexpired signed `fileUrl`, never persisted locally.
    public func fetchDetail(clientID: UUID) async throws -> SessionAnnotationDTO {
        guard let token = deviceToken() else {
            throw SessionAnnotationSyncError.noDeviceToken
        }
        guard let serverID = try await store.serverID(clientID: clientID) else {
            throw SyncDependencyError.parentNotSynced
        }
        return try await apiClient.get("session-annotations/\(serverID)/", authorizationHeader: "DeviceToken \(token)")
    }

    /// Re-fetches and caches a session annotation's transcription; no-ops if the server ID is unknown.
    @discardableResult
    public func refreshTranscription(serverID: Int64) async throws -> Bool {
        guard let token = deviceToken(), try await store.hasLocalRecord(serverID: serverID) else { return false }
        let dto: SessionAnnotationDTO = try await apiClient.get("session-annotations/\(serverID)/", authorizationHeader: "DeviceToken \(token)")
        try await store.updateTranscriptionLocally(serverID: serverID, transcription: dto.transcription, language: dto.language, translation: dto.translation)
        return true
    }

    /// Fetches the raw bytes of an already-synced file annotation, re-fetching the detail record first for a live URL.
    public func downloadFile(clientID: UUID) async throws -> (data: Data, suggestedFilename: String?) {
        guard let token = deviceToken() else {
            throw SessionAnnotationSyncError.noDeviceToken
        }
        let dto = try await fetchDetail(clientID: clientID)
        guard let urlString = dto.fileUrl, let url = URL(string: urlString) else {
            throw SessionAnnotationSyncError.fileUnavailable
        }
        return try await apiClient.downloadData(from: url, authorizationHeader: "DeviceToken \(token)")
    }

    /// Toggles the `scratched` (soft-hide) flag on an already-synced annotation. Online-only.
    public func setScratched(clientID: UUID, scratched: Bool) async throws {
        guard let token = deviceToken() else {
            throw SessionAnnotationSyncError.noDeviceToken
        }
        guard let serverID = try await store.serverID(clientID: clientID) else {
            throw SyncDependencyError.parentNotSynced
        }
        let _: SessionAnnotationDTO = try await apiClient.send(
            "session-annotations/\(serverID)/",
            method: .patch,
            body: UpdateAnnotationScratchedRequest(scratched: scratched),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.setScratchedLocally(clientID: clientID, scratched: scratched)
    }

    /// Hard-deletes an already-synced annotation. Owner/editor-gated server-side; a 403 surfaces as a normal error.
    public func deleteAnnotation(clientID: UUID) async throws {
        guard let token = deviceToken() else {
            throw SessionAnnotationSyncError.noDeviceToken
        }
        guard let serverID = try await store.serverID(clientID: clientID) else {
            throw SyncDependencyError.parentNotSynced
        }
        try await apiClient.sendNoContent(
            "session-annotations/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeLocal(clientID: clientID)
    }
}

public enum SessionAnnotationSyncError: Error {
    case noDeviceToken
    case uploadFailed(String)
    case annotationNotCached
    case fileUnavailable
}

@ModelActor
actor SessionAnnotationStore {
    func upsert(_ dtos: [SessionAnnotationDTO]) throws {
        for dto in dtos {
            guard let sessionClientID = sessionClientID(forServerID: dto.session) else { continue }

            let annotationID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.serverID == annotationID })
            )
            let annotation = existing?.first ?? {
                let created = CachedSessionAnnotation(
                    serverID: dto.id,
                    sessionClientID: sessionClientID,
                    annotationText: dto.annotationText,
                    annotationType: dto.annotationType,
                    order: dto.order,
                    createdAt: dto.createdAt
                )
                modelContext.insert(created)
                return created
            }()
            annotation.sessionClientID = sessionClientID
            annotation.annotationText = dto.annotationText
            annotation.annotationType = dto.annotationType
            annotation.order = dto.order
            annotation.scratched = dto.scratched
            annotation.createdAt = dto.createdAt
        }
        try modelContext.save()
    }

    private func sessionClientID(forServerID sessionServerID: Int64) -> UUID? {
        let match = try? modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == sessionServerID })
        )
        return match?.first?.clientID
    }

    func insertLocalFileOnly(
        clientID: UUID,
        sessionClientID: UUID,
        annotationType: String,
        transcription: String? = nil,
        language: String? = nil,
        translation: String? = nil,
        pendingFileName: String
    ) throws -> UUID {
        let cached = CachedSessionAnnotation(
            clientID: clientID,
            sessionClientID: sessionClientID,
            annotationText: transcription ?? "",
            annotationType: annotationType,
            order: 0,
            transcription: transcription,
            language: language,
            translation: translation,
            pendingFileName: pendingFileName
        )
        modelContext.insert(cached)
        try modelContext.save()
        return cached.clientID
    }

    func fileAnnotationFields(clientID: UUID) throws -> (
        sessionServerID: Int64?, annotationType: String, transcription: String?, language: String?, translation: String?, pendingFileName: String
    ) {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first, let pendingFileName = annotation.pendingFileName else {
            throw SessionAnnotationSyncError.annotationNotCached
        }
        let sessionClientID = annotation.sessionClientID
        let sessionMatch = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.clientID == sessionClientID })
        ).first
        return (sessionMatch?.serverID, annotation.annotationType, annotation.transcription, annotation.language, annotation.translation, pendingFileName)
    }

    func attachFileServerID(clientID: UUID, serverID: Int64) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw SessionAnnotationSyncError.annotationNotCached
        }
        annotation.serverID = serverID
        annotation.pendingFileName = nil
        try modelContext.save()
    }

    func serverID(clientID: UUID) throws -> Int64? {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw SessionAnnotationSyncError.annotationNotCached
        }
        return annotation.serverID
    }

    func hasLocalRecord(serverID: Int64) throws -> Bool {
        try modelContext.fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.serverID == serverID })).first != nil
    }

    func updateTranscriptionLocally(serverID: Int64, transcription: String?, language: String?, translation: String?) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.serverID == serverID })
        ).first else {
            throw SessionAnnotationSyncError.annotationNotCached
        }
        annotation.transcription = transcription
        annotation.language = language
        annotation.translation = translation
        try modelContext.save()
    }

    func setScratchedLocally(clientID: UUID, scratched: Bool) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw SessionAnnotationSyncError.annotationNotCached
        }
        annotation.scratched = scratched
        try modelContext.save()
    }

    func removeLocal(clientID: UUID) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw SessionAnnotationSyncError.annotationNotCached
        }
        modelContext.delete(annotation)
        try modelContext.save()
    }
}
