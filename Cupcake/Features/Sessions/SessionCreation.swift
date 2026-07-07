import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import Foundation
import SwiftData

enum SessionCreationOutcome {
    case success
    case queued
    case failed(message: String)
}

/// Shared create-locally-then-sync-or-queue logic for starting a session.
enum SessionCreation {
    @discardableResult
    static func createSession(
        name: String,
        enabled: Bool,
        protocolClientIDs: [UUID],
        canAuthorOnline: Bool,
        modelContext: ModelContext,
        appSession: AppSession
    ) async -> (clientID: UUID, outcome: SessionCreationOutcome) {
        let session = CachedSession(
            uniqueID: nil,
            name: name,
            enabled: enabled,
            isRunning: true,
            status: "running",
            protocolClientIDs: protocolClientIDs,
            primaryProtocolClientID: protocolClientIDs.first
        )
        modelContext.insert(session)
        try? modelContext.save()
        let clientID = session.clientID

        guard canAuthorOnline else { return (clientID, .success) }
        let services = appSession.makeSyncServices()
        do {
            try await services.sessionSync.syncLocallyCreatedSession(clientID: clientID)
            return (clientID, .success)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateSession(clientID: clientID)
                return (clientID, .queued)
            }
            return (clientID, .failed(message: error.userFacingMessage))
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateSession(clientID: clientID)
            return (clientID, .queued)
        } catch {
            return (clientID, .failed(message: error.userFacingMessage))
        }
    }
}
