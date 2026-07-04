import Foundation
import SwiftData

/// Offline-createable (Phase 2 onward), so — unlike the read-only `Cached*` protocol types —
/// this uses a client-generated `clientID` as its real persistent identity from the start.
/// `serverID` fills in once a create round-trip succeeds. `session`/`step` are referenced by
/// their `clientID`, not their `serverID`, because a locally-created session or step (standalone
/// mode, or not yet synced) may not have a `serverID` at all — resolving to server IDs happens
/// only at the network-call boundary (`StepAnnotationSyncService`), never for local storage.
@Model
public final class CachedStepAnnotation {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var sessionClientID: UUID
    public var stepClientID: UUID
    public var annotationText: String
    public var annotationType: String
    public var order: Int

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        sessionClientID: UUID,
        stepClientID: UUID,
        annotationText: String,
        annotationType: String = "text",
        order: Int = 0
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.sessionClientID = sessionClientID
        self.stepClientID = stepClientID
        self.annotationText = annotationText
        self.annotationType = annotationType
        self.order = order
    }
}
