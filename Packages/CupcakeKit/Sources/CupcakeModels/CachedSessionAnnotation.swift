import Foundation
import SwiftData

/// Offline-createable from Phase 2 on (§3), same as `CachedStepAnnotation` — read-only cache
/// only for now, no create path yet in Phase 1. `session` is referenced by `clientID`, not
/// `serverID` — see `CachedStepAnnotation`'s doc comment for why.
@Model
public final class CachedSessionAnnotation {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var sessionClientID: UUID
    public var annotationText: String
    public var annotationType: String
    public var order: Int

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        sessionClientID: UUID,
        annotationText: String,
        annotationType: String = "text",
        order: Int = 0
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.sessionClientID = sessionClientID
        self.annotationText = annotationText
        self.annotationType = annotationType
        self.order = order
    }
}
