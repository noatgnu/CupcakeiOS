import Foundation
import SwiftData

/// Read-only reference data when fetched from someone else's server-side protocol (§3) — but a
/// protocol can also be authored by this app, either purely locally (standalone/offline mode,
/// where it never gets a `serverID`) or online (where it does). `isLocallyAuthored` — not
/// `serverID == nil` — is what actually governs whether this app lets you keep editing it
/// (`ProtocolDetailView.isEditable`): a protocol this app created online still has a `serverID`
/// (it's synced), but you should still be able to add sections/steps/reagents to your own
/// protocol afterward, same as the reference web app's `protocol-editor.ts` lets its owner keep
/// editing after creation. `serverID == nil` alone would wrongly treat "created online, has a
/// serverID" the same as "someone else's read-only protocol." `clientID` is always the real
/// persistent identity.
@Model
public final class CachedProtocol {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var protocolTitle: String
    public var protocolDescription: String?
    public var enabled: Bool
    public var isLocallyAuthored: Bool

    @Relationship(deleteRule: .cascade, inverse: \CachedProtocolSection.protocolModel)
    public var sections: [CachedProtocolSection] = []

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        protocolTitle: String,
        protocolDescription: String? = nil,
        enabled: Bool,
        isLocallyAuthored: Bool = false
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.protocolTitle = protocolTitle
        self.protocolDescription = protocolDescription
        self.enabled = enabled
        self.isLocallyAuthored = isLocallyAuthored
    }
}
