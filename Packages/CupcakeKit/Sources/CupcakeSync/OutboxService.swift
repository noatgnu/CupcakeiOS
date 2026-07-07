import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Queues and replays creates that couldn't reach the server due to genuine unreachability.
public actor OutboxService {
    private let protocolSync: ProtocolSyncService
    private let sessionSync: SessionSyncService
    private let stepReagentSync: StepReagentSyncService
    private let stepAnnotationSync: StepAnnotationSyncService
    private let sessionAnnotationSync: SessionAnnotationSyncService
    private let inventorySync: InventorySyncService
    private let instrumentSync: InstrumentSyncService
    private let projectSync: ProjectSyncService
    private let instrumentJobSync: InstrumentJobSyncService
    private let store: OutboxStore

    public init(
        modelContainer: ModelContainer,
        protocolSync: ProtocolSyncService,
        sessionSync: SessionSyncService,
        stepReagentSync: StepReagentSyncService,
        stepAnnotationSync: StepAnnotationSyncService,
        sessionAnnotationSync: SessionAnnotationSyncService,
        inventorySync: InventorySyncService,
        instrumentSync: InstrumentSyncService,
        projectSync: ProjectSyncService,
        instrumentJobSync: InstrumentJobSyncService
    ) {
        self.protocolSync = protocolSync
        self.sessionSync = sessionSync
        self.stepReagentSync = stepReagentSync
        self.stepAnnotationSync = stepAnnotationSync
        self.sessionAnnotationSync = sessionAnnotationSync
        self.inventorySync = inventorySync
        self.instrumentSync = instrumentSync
        self.projectSync = projectSync
        self.instrumentJobSync = instrumentJobSync
        self.store = OutboxStore(modelContainer: modelContainer)
    }

    public func enqueueCreateProtocol(clientID: UUID, title: String, description: String?, enabled: Bool) async throws {
        let payload = CreateProtocolPayload(title: title, description: description, enabled: enabled)
        let data = try JSONEncoder().encode(payload)
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createProtocol.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateSection(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createSection.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateStep(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createStep.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateSession(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createSession.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateStepReagent(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createStepReagent.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateTextAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createTextAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateStoredReagent(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createStoredReagent.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateReagentAction(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createReagentAction.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateInstrumentUsage(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createInstrumentUsage.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateProject(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createProject.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateInstrumentJob(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createInstrumentJob.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateStepAudioAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createStepAudioAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateSessionAudioAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createSessionAudioAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateStepImageAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createStepImageAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateSessionImageAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createSessionImageAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateStepVideoAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createStepVideoAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateSessionVideoAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createSessionVideoAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateStepSketchAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createStepSketchAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    public func enqueueCreateSessionSketchAnnotation(clientID: UUID) async throws {
        let data = try JSONEncoder().encode(EmptyOutboxPayload())
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createSessionSketchAnnotation.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    /// Attempts every pending/failed entry in FIFO order.
    public func replayPending() async {
        let entries = (try? await store.fetchPending()) ?? []
        for entry in entries {
            do {
                try await replay(entry)
                try? await store.delete(entry.id)
            } catch let error as APIError {
                if case .transport = error {
                    try? await store.recordRetry(entry.id, error: error.localizedDescription)
                } else {
                    try? await store.markFailed(entry.id, error: error.localizedDescription)
                }
            } catch SyncDependencyError.parentNotSynced {
                try? await store.recordRetry(entry.id, error: "Waiting for its parent to sync first")
            } catch {
                try? await store.markFailed(entry.id, error: error.localizedDescription)
            }
        }
    }

    private func replay(_ entry: OutboxEntrySnapshot) async throws {
        guard let operationType = OutboxOperationType(rawValue: entry.operationType) else { return }
        switch operationType {
        case .createProtocol:
            try await protocolSync.syncLocallyCreatedProtocol(clientID: entry.relatedClientID)
        case .createSection:
            try await protocolSync.syncLocallyCreatedSection(clientID: entry.relatedClientID)
        case .createStep:
            try await protocolSync.syncLocallyCreatedStep(clientID: entry.relatedClientID)
        case .createSession:
            try await sessionSync.syncLocallyCreatedSession(clientID: entry.relatedClientID)
        case .createStepReagent:
            try await stepReagentSync.syncLocallyCreatedStepReagent(clientID: entry.relatedClientID)
        case .createTextAnnotation:
            try await stepAnnotationSync.syncLocallyCreatedTextAnnotation(clientID: entry.relatedClientID)
        case .createStoredReagent:
            try await inventorySync.syncLocallyCreatedStoredReagent(clientID: entry.relatedClientID)
        case .createReagentAction:
            try await inventorySync.syncLocallyCreatedReagentAction(clientID: entry.relatedClientID)
        case .createInstrumentUsage:
            try await instrumentSync.syncLocallyCreatedInstrumentUsage(clientID: entry.relatedClientID)
        case .createProject:
            try await projectSync.syncLocallyCreatedProject(clientID: entry.relatedClientID)
        case .createInstrumentJob:
            try await instrumentJobSync.syncLocallyCreatedInstrumentJob(clientID: entry.relatedClientID)
        case .createStepAudioAnnotation:
            try await stepAnnotationSync.syncLocallyCreatedAudioAnnotation(clientID: entry.relatedClientID)
        case .createSessionAudioAnnotation:
            try await sessionAnnotationSync.syncLocallyCreatedAudioAnnotation(clientID: entry.relatedClientID)
        case .createStepImageAnnotation:
            try await stepAnnotationSync.syncLocallyCreatedImageAnnotation(clientID: entry.relatedClientID)
        case .createSessionImageAnnotation:
            try await sessionAnnotationSync.syncLocallyCreatedImageAnnotation(clientID: entry.relatedClientID)
        case .createStepVideoAnnotation:
            try await stepAnnotationSync.syncLocallyCreatedVideoAnnotation(clientID: entry.relatedClientID)
        case .createSessionVideoAnnotation:
            try await sessionAnnotationSync.syncLocallyCreatedVideoAnnotation(clientID: entry.relatedClientID)
        case .createStepSketchAnnotation:
            try await stepAnnotationSync.syncLocallyCreatedSketchAnnotation(clientID: entry.relatedClientID)
        case .createSessionSketchAnnotation:
            try await sessionAnnotationSync.syncLocallyCreatedSketchAnnotation(clientID: entry.relatedClientID)
        }
    }
}

/// A plain, `Sendable` snapshot of the fields `OutboxService.replay(_:)` needs.
struct OutboxEntrySnapshot: Sendable {
    let id: UUID
    let operationType: String
    let relatedClientID: UUID
}

@ModelActor
actor OutboxStore {
    /// Assigns a strictly-increasing `sequence` value regardless of `Date()` resolution.
    func enqueue(_ entry: OutboxEntry) throws {
        let maxSequence = try modelContext.fetch(
            FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        ).first?.sequence ?? 0
        entry.sequence = maxSequence + 1
        modelContext.insert(entry)
        try modelContext.save()
    }

    func fetchPending() throws -> [OutboxEntrySnapshot] {
        try modelContext.fetch(FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.sequence)]))
            .map { OutboxEntrySnapshot(id: $0.id, operationType: $0.operationType, relatedClientID: $0.relatedClientID) }
    }

    func delete(_ id: UUID) throws {
        guard let entry = try modelContext.fetch(FetchDescriptor<OutboxEntry>(predicate: #Predicate { $0.id == id })).first else { return }
        modelContext.delete(entry)
        try modelContext.save()
    }

    func recordRetry(_ id: UUID, error: String) throws {
        guard let entry = try modelContext.fetch(FetchDescriptor<OutboxEntry>(predicate: #Predicate { $0.id == id })).first else { return }
        entry.retryCount += 1
        entry.lastError = error
        try modelContext.save()
    }

    func markFailed(_ id: UUID, error: String) throws {
        guard let entry = try modelContext.fetch(FetchDescriptor<OutboxEntry>(predicate: #Predicate { $0.id == id })).first else { return }
        entry.status = OutboxEntryStatus.failed.rawValue
        entry.lastError = error
        try modelContext.save()
    }
}
