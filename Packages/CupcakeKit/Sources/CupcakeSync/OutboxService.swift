import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Queues and replays creates that couldn't reach the server due to genuine unreachability
/// (`APIError.transport`) — the record itself is always created locally first (see
/// `NewProtocolView`'s create-locally-then-sync flow), so nothing is lost or blocked on the
/// network; this only handles getting it to the server once connectivity comes back, via
/// `NWPathMonitor`-triggered or manual `replayPending()` calls.
///
/// `createProtocol`/`createSection`/`createStep`/`createSession`/`createStepReagent`/
/// `createTextAnnotation` are all wired up end to end — every local-authoring create operation
/// in this app goes through this path when signed in. Extending to a future new operation is the
/// same shape: add a `Create*Payload` (`CupcakeModels`) if it needs one, an `enqueueCreate*`, and
/// a case in `replay(_:)` calling the matching `sync*` method on the relevant sync service.
///
/// Section/step/session/annotation replay can fail with `SyncDependencyError.parentNotSynced` — its parent
/// hasn't synced yet, most often because *that* parent's own outbox entry is still ahead of it
/// in the queue (strict FIFO `sequence` order normally handles this: a protocol enqueued before
/// its section replays first and unblocks it) — but a parent could also still be failing for its
/// own reasons. Either way this is an ordering issue, not a real error, so it's retried exactly
/// like a connectivity failure rather than marked `.failed`.
public actor OutboxService {
    private let protocolSync: ProtocolSyncService
    private let sessionSync: SessionSyncService
    private let stepReagentSync: StepReagentSyncService
    private let stepAnnotationSync: StepAnnotationSyncService
    private let inventorySync: InventorySyncService
    private let instrumentSync: InstrumentSyncService
    private let store: OutboxStore

    public init(
        modelContainer: ModelContainer,
        protocolSync: ProtocolSyncService,
        sessionSync: SessionSyncService,
        stepReagentSync: StepReagentSyncService,
        stepAnnotationSync: StepAnnotationSyncService,
        inventorySync: InventorySyncService,
        instrumentSync: InstrumentSyncService
    ) {
        self.protocolSync = protocolSync
        self.sessionSync = sessionSync
        self.stepReagentSync = stepReagentSync
        self.stepAnnotationSync = stepAnnotationSync
        self.inventorySync = inventorySync
        self.instrumentSync = instrumentSync
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

    /// Attempts every pending/failed entry in FIFO (`createdAt`) order. An entry that still
    /// fails due to unreachability (or an unmet ordering dependency, see the type's doc comment)
    /// is left in place with its retry count bumped for next time; one that fails for a real,
    /// non-connectivity reason is marked `.failed` with the error message so a "Sync Issues"
    /// screen can surface it, and isn't retried automatically again.
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
        }
    }
}

/// A plain, `Sendable` snapshot of the fields `OutboxService.replay(_:)` needs — `OutboxEntry`
/// itself is a SwiftData `@Model`, bound to `OutboxStore`'s own `ModelContext`, so it can't
/// safely cross to `OutboxService`'s actor the way its own stored properties can.
struct OutboxEntrySnapshot: Sendable {
    let id: UUID
    let operationType: String
    let relatedClientID: UUID
}

@ModelActor
actor OutboxStore {
    /// Assigns strictly-increasing `sequence` values regardless of `Date()` resolution — see
    /// `OutboxEntry.sequence`'s doc comment.
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
