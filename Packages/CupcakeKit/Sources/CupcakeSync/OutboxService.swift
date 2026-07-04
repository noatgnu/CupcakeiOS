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
/// Only `OutboxOperationType.createProtocol` is wired up end to end right now — the first
/// vertical slice through the whole outbox mechanism (enqueue → persist → replay → attach
/// `serverID` to the existing local record). Extending to section/step/reagent/session creation
/// is the same shape: add a `Create*Payload` (`CupcakeModels`), an `enqueueCreate*`, and a case
/// in `replay(_:)` calling the matching `sync*` method on the relevant sync service.
public actor OutboxService {
    private let protocolSync: ProtocolSyncService
    private let store: OutboxStore

    public init(modelContainer: ModelContainer, protocolSync: ProtocolSyncService) {
        self.protocolSync = protocolSync
        self.store = OutboxStore(modelContainer: modelContainer)
    }

    public func enqueueCreateProtocol(clientID: UUID, title: String, description: String?, enabled: Bool) async throws {
        let payload = CreateProtocolPayload(title: title, description: description, enabled: enabled)
        let data = try JSONEncoder().encode(payload)
        try await store.enqueue(OutboxEntry(operationType: OutboxOperationType.createProtocol.rawValue, payloadJSON: data, relatedClientID: clientID))
    }

    /// Attempts every pending/failed entry in FIFO (`createdAt`) order. An entry that still
    /// fails due to unreachability is left in place with its retry count bumped for next time;
    /// one that fails for a real, non-connectivity reason is marked `.failed` with the error
    /// message so a "Sync Issues" screen can surface it, and isn't retried automatically again.
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
    func enqueue(_ entry: OutboxEntry) throws {
        modelContext.insert(entry)
        try modelContext.save()
    }

    func fetchPending() throws -> [OutboxEntrySnapshot] {
        try modelContext.fetch(FetchDescriptor<OutboxEntry>(sortBy: [SortDescriptor(\.createdAt)]))
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
