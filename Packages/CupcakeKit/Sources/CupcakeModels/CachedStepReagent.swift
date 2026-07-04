import Foundation
import SwiftData

/// Links a step to a reagent with a quantity — completes the Protocol -> Section -> Step ->
/// StepReagent authoring hierarchy for locally-created protocols, not just read-only display for
/// server-synced ones. `step`/`reagent` are referenced by `clientID`, not `serverID` — same
/// reasoning as `CachedStepAnnotation`: a locally-authored step or reagent may have no `serverID`
/// at all. Verified non-nullable against `ccrv/models.py`'s `StepReagent`: `step`/`reagent` are
/// required FKs, `quantity` is a required `FloatField` with no default, `scalable` defaults to
/// `False`, `scalable_factor` defaults to `1.0`.
@Model
public final class CachedStepReagent {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var stepClientID: UUID
    public var reagentClientID: UUID
    public var quantity: Double
    public var scalable: Bool
    public var scalableFactor: Double

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        stepClientID: UUID,
        reagentClientID: UUID,
        quantity: Double,
        scalable: Bool = false,
        scalableFactor: Double = 1.0
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.stepClientID = stepClientID
        self.reagentClientID = reagentClientID
        self.quantity = quantity
        self.scalable = scalable
        self.scalableFactor = scalableFactor
    }
}
