import Foundation
import SwiftData

/// Uses the same client-generated-identity pattern as the offline-createable models: `clientID`
/// is always the real persistent identity, `serverID` is filled in once this step is (or was)
/// fetched from the server. In standalone/offline mode a step may never get a `serverID` at all —
/// a step created entirely locally in a locally-created protocol has none, permanently.
/// `section` is optional to match the backend's own nullable `step_section` FK (`ccrv/models.py`)
/// — a step can exist unassigned to any section. Neither this app nor the reference Angular
/// frontend ever fetches or displays such a step (both only reach steps via a section), so this
/// is a documented, matched limitation, not an oversight.
@Model
public final class CachedProtocolStep {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var stepDescription: String
    public var order: Int
    /// Seconds (not minutes — see `ProtocolStepDTO`'s doc comment) — real field for
    /// protocols.io-imported protocols.
    public var stepDuration: Int?
    public var section: CachedProtocolSection?

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        stepDescription: String,
        order: Int,
        stepDuration: Int? = nil,
        section: CachedProtocolSection? = nil
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.stepDescription = stepDescription
        self.order = order
        self.stepDuration = stepDuration
        self.section = section
    }
}
