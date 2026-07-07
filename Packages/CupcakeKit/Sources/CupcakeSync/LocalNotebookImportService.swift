import CupcakeModels
import Foundation
import SwiftData

/// Enqueues every not-yet-synced local record into the outbox and replays it.
public actor LocalNotebookImportService {
    private let outboxSync: OutboxService
    private let store: LocalNotebookImportStore

    public init(modelContainer: ModelContainer, outboxSync: OutboxService) {
        self.outboxSync = outboxSync
        self.store = LocalNotebookImportStore(modelContainer: modelContainer)
    }

    public func countLocalOnlyRecords() async throws -> Int {
        try await store.countLocalOnlyRecords()
    }

    public func importAll() async {
        let records = (try? await store.fetchLocalOnlyRecords()) ?? LocalOnlyRecords()

        for protocolRecord in records.protocols {
            try? await outboxSync.enqueueCreateProtocol(
                clientID: protocolRecord.clientID,
                title: protocolRecord.title,
                description: protocolRecord.description,
                enabled: protocolRecord.enabled
            )
        }
        for clientID in records.sectionClientIDs {
            try? await outboxSync.enqueueCreateSection(clientID: clientID)
        }
        for clientID in records.stepClientIDs {
            try? await outboxSync.enqueueCreateStep(clientID: clientID)
        }
        for clientID in records.sessionClientIDs {
            try? await outboxSync.enqueueCreateSession(clientID: clientID)
        }
        for clientID in records.stepReagentClientIDs {
            try? await outboxSync.enqueueCreateStepReagent(clientID: clientID)
        }
        for clientID in records.textAnnotationClientIDs {
            try? await outboxSync.enqueueCreateTextAnnotation(clientID: clientID)
        }
        for clientID in records.stepAudioAnnotationClientIDs {
            try? await outboxSync.enqueueCreateStepAudioAnnotation(clientID: clientID)
        }
        for clientID in records.sessionAudioAnnotationClientIDs {
            try? await outboxSync.enqueueCreateSessionAudioAnnotation(clientID: clientID)
        }
        for clientID in records.projectClientIDs {
            try? await outboxSync.enqueueCreateProject(clientID: clientID)
        }
        for clientID in records.instrumentJobClientIDs {
            try? await outboxSync.enqueueCreateInstrumentJob(clientID: clientID)
        }
        for clientID in records.storedReagentClientIDs {
            try? await outboxSync.enqueueCreateStoredReagent(clientID: clientID)
        }
        for clientID in records.reagentActionClientIDs {
            try? await outboxSync.enqueueCreateReagentAction(clientID: clientID)
        }
        for clientID in records.instrumentUsageClientIDs {
            try? await outboxSync.enqueueCreateInstrumentUsage(clientID: clientID)
        }

        for _ in 0..<5 {
            await outboxSync.replayPending()
        }
    }
}

struct LocalOnlyRecords: Sendable {
    struct ProtocolSnapshot: Sendable {
        let clientID: UUID
        let title: String
        let description: String?
        let enabled: Bool
    }

    var protocols: [ProtocolSnapshot] = []
    var sectionClientIDs: [UUID] = []
    var stepClientIDs: [UUID] = []
    var sessionClientIDs: [UUID] = []
    var stepReagentClientIDs: [UUID] = []
    var textAnnotationClientIDs: [UUID] = []
    var stepAudioAnnotationClientIDs: [UUID] = []
    var sessionAudioAnnotationClientIDs: [UUID] = []
    var storedReagentClientIDs: [UUID] = []
    var reagentActionClientIDs: [UUID] = []
    var instrumentUsageClientIDs: [UUID] = []
    var projectClientIDs: [UUID] = []
    var instrumentJobClientIDs: [UUID] = []

    var total: Int {
        protocols.count + sectionClientIDs.count + stepClientIDs.count + sessionClientIDs.count
            + stepReagentClientIDs.count + textAnnotationClientIDs.count + stepAudioAnnotationClientIDs.count
            + sessionAudioAnnotationClientIDs.count + storedReagentClientIDs.count + reagentActionClientIDs.count
            + instrumentUsageClientIDs.count + projectClientIDs.count + instrumentJobClientIDs.count
    }
}

@ModelActor
actor LocalNotebookImportStore {
    func countLocalOnlyRecords() throws -> Int {
        try fetchLocalOnlyRecords().total
    }

    func fetchLocalOnlyRecords() throws -> LocalOnlyRecords {
        var records = LocalOnlyRecords()
        records.protocols = try modelContext.fetch(
            FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.serverID == nil })
        ).map {
            LocalOnlyRecords.ProtocolSnapshot(clientID: $0.clientID, title: $0.protocolTitle, description: $0.protocolDescription, enabled: $0.enabled)
        }
        records.sectionClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedProtocolSection>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        records.stepClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        records.sessionClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        records.stepReagentClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedStepReagent>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        records.textAnnotationClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.serverID == nil && $0.annotationType == "text" })
        ).map(\.clientID)
        records.stepAudioAnnotationClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.serverID == nil && $0.annotationType == "audio" })
        ).map(\.clientID)
        records.sessionAudioAnnotationClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.serverID == nil && $0.annotationType == "audio" })
        ).map(\.clientID)
        records.storedReagentClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedStoredReagent>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        records.reagentActionClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedReagentAction>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        records.instrumentUsageClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedInstrumentUsage>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        records.projectClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedProject>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        records.instrumentJobClientIDs = try modelContext.fetch(
            FetchDescriptor<CachedInstrumentJob>(predicate: #Predicate { $0.serverID == nil })
        ).map(\.clientID)
        return records
    }
}
