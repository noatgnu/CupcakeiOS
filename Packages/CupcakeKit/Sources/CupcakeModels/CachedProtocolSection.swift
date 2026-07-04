import Foundation
import SwiftData

@Model
public final class CachedProtocolSection {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var sectionDescription: String?
    public var order: Int
    /// Seconds (not minutes — see `ProtocolStepDTO`'s doc comment) — real field for
    /// protocols.io-imported protocols, see `ProtocolSectionDTO`. Independently editable in the
    /// reference web app, not auto-computed from step durations there — this app deliberately
    /// diverges by auto-summing it from its steps' durations instead (an explicit product
    /// decision for local authoring, not an unverified assumption).
    public var sectionDuration: Int?
    public var protocolModel: CachedProtocol?

    @Relationship(deleteRule: .cascade, inverse: \CachedProtocolStep.section)
    public var steps: [CachedProtocolStep] = []

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        sectionDescription: String? = nil,
        order: Int,
        sectionDuration: Int? = nil,
        protocolModel: CachedProtocol? = nil
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.sectionDescription = sectionDescription
        self.order = order
        self.sectionDuration = sectionDuration
        self.protocolModel = protocolModel
    }
}
