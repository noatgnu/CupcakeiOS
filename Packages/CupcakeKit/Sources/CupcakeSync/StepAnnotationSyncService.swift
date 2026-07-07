import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Creates and syncs step-level text and file (audio/photo/video/sketch) annotations.
public actor StepAnnotationSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: StepAnnotationStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = StepAnnotationStore(modelContainer: modelContainer)
    }

    @discardableResult
    public func createTextAnnotation(sessionClientID: UUID, stepClientID: UUID, text: String) async throws -> UUID {
        try await store.insertLocalOnly(sessionClientID: sessionClientID, stepClientID: stepClientID, text: text, annotationType: "text")
    }

    /// Creates a calculator annotation locally via the same `annotation_data` shortcut as text.
    @discardableResult
    public func createCalculatorAnnotation(sessionClientID: UUID, stepClientID: UUID, historyJSON: String) async throws -> UUID {
        try await store.insertLocalOnly(sessionClientID: sessionClientID, stepClientID: stepClientID, text: historyJSON, annotationType: "calculator")
    }

    /// Same shape as `createCalculatorAnnotation`, for the molarity calculator's own history JSON.
    @discardableResult
    public func createMolarityCalculatorAnnotation(sessionClientID: UUID, stepClientID: UUID, historyJSON: String) async throws -> UUID {
        try await store.insertLocalOnly(sessionClientID: sessionClientID, stepClientID: stepClientID, text: historyJSON, annotationType: "mcalculator")
    }

    /// Pushes an already locally-created text-shaped annotation (text, calculator, or molarity calculator) to the server.
    @discardableResult
    public func syncLocallyCreatedTextAnnotation(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw StepAnnotationSyncError.noDeviceToken
        }
        let fields = try await store.annotationFields(clientID: clientID)
        guard let sessionServerID = fields.sessionServerID, let stepServerID = fields.stepServerID else {
            throw SyncDependencyError.parentNotSynced
        }
        let dto: StepAnnotationDTO = try await apiClient.send(
            "step-annotations/",
            method: .post,
            body: CreateStepAnnotationRequest(
                session: sessionServerID,
                step: stepServerID,
                annotationData: AnnotationDataRequest(annotationType: fields.annotationType, annotation: fields.text)
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(clientID: clientID, dto: dto)
        return dto.id
    }

    /// Thin alias over `syncLocallyCreatedTextAnnotation` for a clearer call-site name.
    @discardableResult
    public func syncLocallyCreatedCalculatorAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedTextAnnotation(clientID: clientID)
    }

    @discardableResult
    public func syncLocallyCreatedMolarityCalculatorAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedTextAnnotation(clientID: clientID)
    }

    /// Online-only 3-call composite (usage -> step-annotation -> link). Requires the session and step to already have `serverID`s.
    @discardableResult
    public func createBookingAnnotation(
        sessionServerID: Int64,
        sessionClientID: UUID,
        stepServerID: Int64,
        stepClientID: UUID,
        instrumentServerID: Int64,
        instrumentName: String,
        timeStarted: String,
        timeEnded: String?,
        usageDescription: String
    ) async throws -> UUID {
        guard let token = deviceToken() else {
            throw StepAnnotationSyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"

        let usage: InstrumentUsageDTO = try await apiClient.send(
            "instrument-usage/",
            method: .post,
            body: CreateInstrumentUsageRequest(
                instrument: instrumentServerID,
                timeStarted: timeStarted,
                timeEnded: timeEnded,
                description: usageDescription,
                maintenance: false
            ),
            authorizationHeader: authorization
        )

        let annotationText = "Instrument booking: \(instrumentName)"
        let annotation: StepAnnotationDTO = try await apiClient.send(
            "step-annotations/",
            method: .post,
            body: CreateStepAnnotationRequest(
                session: sessionServerID,
                step: stepServerID,
                annotationData: AnnotationDataRequest(annotationType: "booking", annotation: annotationText)
            ),
            authorizationHeader: authorization
        )

        _ = try await apiClient.send(
            "instrument-usage-step-annotations/",
            method: .post,
            body: CreateInstrumentUsageStepAnnotationRequest(stepAnnotation: annotation.id, instrumentUsage: usage.id),
            authorizationHeader: authorization
        ) as InstrumentUsageStepAnnotationDTO

        return try await store.insertSynced(
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
            dto: annotation,
            instrumentUsageServerID: usage.id
        )
    }

    /// Persists the recorded file locally and inserts a local record, with no network call.
    @discardableResult
    public func createAudioAnnotation(
        sessionClientID: UUID,
        stepClientID: UUID,
        recordedFileURL: URL,
        transcription: String?,
        language: String?,
        translation: String?
    ) async throws -> UUID {
        try await createFileAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
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
    public func createImageAnnotation(sessionClientID: UUID, stepClientID: UUID, imageData: Data) async throws -> UUID {
        let clientID = UUID()
        let fileName = try PendingAnnotationFileStorage.persist(imageData, clientID: clientID, fileExtension: "jpg")
        return try await store.insertLocalFileOnly(
            clientID: clientID,
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
            annotationType: "image",
            pendingFileName: fileName
        )
    }

    /// Persists a video's file data locally and inserts a local record, with no network call.
    @discardableResult
    public func createVideoAnnotation(
        sessionClientID: UUID,
        stepClientID: UUID,
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
            stepClientID: stepClientID,
            annotationType: "video",
            transcription: transcription,
            language: language,
            translation: translation,
            pendingFileName: fileName
        )
    }

    /// Persists a sketch's JSON vector data locally and inserts a local record, with no network call.
    @discardableResult
    public func createSketchAnnotation(sessionClientID: UUID, stepClientID: UUID, sketchData: Data) async throws -> UUID {
        let clientID = UUID()
        let fileName = try PendingAnnotationFileStorage.persist(sketchData, clientID: clientID, fileExtension: "json")
        return try await store.insertLocalFileOnly(
            clientID: clientID,
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
            annotationType: "sketch",
            pendingFileName: fileName
        )
    }

    /// Persists any not-yet-synced file annotation (audio, photo, video) locally with no network call.
    @discardableResult
    public func createFileAnnotation(
        sessionClientID: UUID,
        stepClientID: UUID,
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
            stepClientID: stepClientID,
            annotationType: annotationType,
            transcription: transcription,
            language: language,
            translation: translation,
            pendingFileName: fileName
        )
    }

    /// Pushes an already locally-created audio annotation to the server and deletes the local copy.
    @discardableResult
    public func syncLocallyCreatedAudioAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedFileAnnotation(clientID: clientID)
    }

    /// Pushes an already locally-created photo annotation to the server and deletes the local copy.
    @discardableResult
    public func syncLocallyCreatedImageAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedFileAnnotation(clientID: clientID)
    }

    /// Pushes an already locally-created video annotation to the server and deletes the local copy.
    @discardableResult
    public func syncLocallyCreatedVideoAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedFileAnnotation(clientID: clientID)
    }

    /// Pushes an already locally-created sketch annotation to the server and deletes the local copy.
    @discardableResult
    public func syncLocallyCreatedSketchAnnotation(clientID: UUID) async throws -> Int64 {
        try await syncLocallyCreatedFileAnnotation(clientID: clientID)
    }

    /// Pushes any not-yet-synced file annotation, deriving its MIME type from the annotation type and file extension.
    @discardableResult
    public func syncLocallyCreatedFileAnnotation(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw StepAnnotationSyncError.noDeviceToken
        }
        let fields = try await store.fileAnnotationFields(clientID: clientID)
        guard let sessionServerID = fields.sessionServerID, let stepServerID = fields.stepServerID else {
            throw SyncDependencyError.parentNotSynced
        }
        let authorization = "DeviceToken \(token)"
        let fileURL = PendingAnnotationFileStorage.url(forFileName: fields.pendingFileName)
        let fileData = try Data(contentsOf: fileURL)
        let checksum = SHA256Checksum.hexDigest(of: fileData)
        let mimeType = AnnotationMimeType.mimeType(annotationType: fields.annotationType, fileExtension: fileURL.pathExtension)

        var form = MultipartFormBuilder()
        form.addField(name: "session_id", value: String(sessionServerID))
        form.addField(name: "step_id", value: String(stepServerID))
        form.addField(name: "annotation_type", value: fields.annotationType)
        form.addField(name: "auto_transcribe", value: fields.transcription == nil && ["audio", "video"].contains(fields.annotationType) ? "true" : "false")
        form.addField(name: "sha256", value: checksum)
        form.addField(name: "filename", value: fileURL.lastPathComponent)
        form.addFile(name: "file", filename: fileURL.lastPathComponent, mimeType: mimeType, data: fileData)

        let response: AnnotationChunkedUploadResponse = try await apiClient.sendMultipart(
            "upload/step-annotation-chunks/",
            body: form,
            authorizationHeader: authorization
        )
        if let warning = response.warning {
            throw StepAnnotationSyncError.uploadFailed(warning)
        }
        guard let stepAnnotationID = response.stepAnnotationId else {
            throw StepAnnotationSyncError.uploadFailed(response.message ?? "Upload did not return a step annotation id")
        }

        if fields.transcription != nil || fields.translation != nil {
            let _: StepAnnotationDTO = try await apiClient.send(
                "step-annotations/\(stepAnnotationID)/",
                method: .patch,
                body: UpdateStepAnnotationTranscriptionRequest(transcription: fields.transcription, language: fields.language, translation: fields.translation),
                authorizationHeader: authorization
            )
        }

        PendingAnnotationFileStorage.remove(fileName: fields.pendingFileName)
        try await store.attachFileServerID(clientID: clientID, serverID: stepAnnotationID)
        return stepAnnotationID
    }

    /// Fetches a fresh copy of an already-synced annotation, for a live, unexpired signed `fileUrl`, never persisted locally.
    public func fetchDetail(clientID: UUID) async throws -> StepAnnotationDTO {
        guard let token = deviceToken() else {
            throw StepAnnotationSyncError.noDeviceToken
        }
        guard let serverID = try await store.serverID(clientID: clientID) else {
            throw SyncDependencyError.parentNotSynced
        }
        return try await apiClient.get("step-annotations/\(serverID)/", authorizationHeader: "DeviceToken \(token)")
    }

    /// Re-fetches and caches a step annotation's transcription; no-ops if the server ID is unknown.
    @discardableResult
    public func refreshTranscription(serverID: Int64) async throws -> Bool {
        guard let token = deviceToken(), try await store.hasLocalRecord(serverID: serverID) else { return false }
        let dto: StepAnnotationDTO = try await apiClient.get("step-annotations/\(serverID)/", authorizationHeader: "DeviceToken \(token)")
        try await store.updateTranscriptionLocally(serverID: serverID, transcription: dto.transcription, language: dto.language, translation: dto.translation)
        return true
    }

    /// Fetches the raw bytes of an already-synced file annotation, re-fetching the detail record first for a live URL.
    public func downloadFile(clientID: UUID) async throws -> (data: Data, suggestedFilename: String?) {
        guard let token = deviceToken() else {
            throw StepAnnotationSyncError.noDeviceToken
        }
        let dto = try await fetchDetail(clientID: clientID)
        guard let urlString = dto.fileUrl, let url = URL(string: urlString) else {
            throw StepAnnotationSyncError.fileUnavailable
        }
        return try await apiClient.downloadData(from: url, authorizationHeader: "DeviceToken \(token)")
    }

    /// Toggles the `scratched` (soft-hide) flag on an already-synced annotation. Online-only.
    public func setScratched(clientID: UUID, scratched: Bool) async throws {
        guard let token = deviceToken() else {
            throw StepAnnotationSyncError.noDeviceToken
        }
        guard let serverID = try await store.serverID(clientID: clientID) else {
            throw SyncDependencyError.parentNotSynced
        }
        let _: StepAnnotationDTO = try await apiClient.send(
            "step-annotations/\(serverID)/",
            method: .patch,
            body: UpdateAnnotationScratchedRequest(scratched: scratched),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.setScratchedLocally(clientID: clientID, scratched: scratched)
    }

    /// Hard-deletes an already-synced annotation. Owner/editor-gated server-side; a 403 surfaces as a normal error.
    public func deleteAnnotation(clientID: UUID) async throws {
        guard let token = deviceToken() else {
            throw StepAnnotationSyncError.noDeviceToken
        }
        guard let serverID = try await store.serverID(clientID: clientID) else {
            throw SyncDependencyError.parentNotSynced
        }
        try await apiClient.sendNoContent(
            "step-annotations/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeLocal(clientID: clientID)
    }
}

public enum StepAnnotationSyncError: Error {
    case noDeviceToken
    case annotationNotCached
    case uploadFailed(String)
    case fileUnavailable
}

@ModelActor
actor StepAnnotationStore {
    func insertLocalOnly(sessionClientID: UUID, stepClientID: UUID, text: String, annotationType: String) throws -> UUID {
        let cached = CachedStepAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
            annotationText: text,
            annotationType: annotationType,
            order: 0
        )
        modelContext.insert(cached)
        try modelContext.save()
        return cached.clientID
    }

    /// Inserts a local record that's already synced, for online-only flows like booking annotations.
    func insertSynced(sessionClientID: UUID, stepClientID: UUID, dto: StepAnnotationDTO, instrumentUsageServerID: Int64? = nil) throws -> UUID {
        let cached = CachedStepAnnotation(
            serverID: dto.id,
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
            annotationText: dto.annotationText,
            annotationType: dto.annotationType,
            order: dto.order,
            instrumentUsageServerID: instrumentUsageServerID,
            createdAt: dto.createdAt
        )
        modelContext.insert(cached)
        try modelContext.save()
        return cached.clientID
    }

    func annotationFields(clientID: UUID) throws -> (sessionServerID: Int64?, stepServerID: Int64?, text: String, annotationType: String) {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        let sessionClientID = annotation.sessionClientID
        let sessionMatch = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.clientID == sessionClientID })
        ).first
        let stepClientID = annotation.stepClientID
        let stepMatch = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.clientID == stepClientID })
        ).first
        return (sessionMatch?.serverID, stepMatch?.serverID, annotation.annotationText, annotation.annotationType)
    }

    /// Attaches a newly-assigned `serverID` to the existing local record matched by `clientID`.
    func attachServerID(clientID: UUID, dto: StepAnnotationDTO) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        annotation.serverID = dto.id
        annotation.annotationText = dto.annotationText
        annotation.annotationType = dto.annotationType
        annotation.order = dto.order
        annotation.scratched = dto.scratched
        annotation.createdAt = dto.createdAt
        try modelContext.save()
    }

    func insertLocalFileOnly(
        clientID: UUID,
        sessionClientID: UUID,
        stepClientID: UUID,
        annotationType: String,
        transcription: String? = nil,
        language: String? = nil,
        translation: String? = nil,
        pendingFileName: String
    ) throws -> UUID {
        let cached = CachedStepAnnotation(
            clientID: clientID,
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
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
        sessionServerID: Int64?, stepServerID: Int64?, annotationType: String, transcription: String?, language: String?, translation: String?, pendingFileName: String
    ) {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first, let pendingFileName = annotation.pendingFileName else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        let sessionClientID = annotation.sessionClientID
        let sessionMatch = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.clientID == sessionClientID })
        ).first
        let stepClientID = annotation.stepClientID
        let stepMatch = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.clientID == stepClientID })
        ).first
        return (sessionMatch?.serverID, stepMatch?.serverID, annotation.annotationType, annotation.transcription, annotation.language, annotation.translation, pendingFileName)
    }

    func attachFileServerID(clientID: UUID, serverID: Int64) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        annotation.serverID = serverID
        annotation.pendingFileName = nil
        try modelContext.save()
    }

    func serverID(clientID: UUID) throws -> Int64? {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        return annotation.serverID
    }

    func hasLocalRecord(serverID: Int64) throws -> Bool {
        try modelContext.fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.serverID == serverID })).first != nil
    }

    func updateTranscriptionLocally(serverID: Int64, transcription: String?, language: String?, translation: String?) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.serverID == serverID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        annotation.transcription = transcription
        annotation.language = language
        annotation.translation = translation
        try modelContext.save()
    }

    func setScratchedLocally(clientID: UUID, scratched: Bool) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        annotation.scratched = scratched
        try modelContext.save()
    }

    func removeLocal(clientID: UUID) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        modelContext.delete(annotation)
        try modelContext.save()
    }
}
