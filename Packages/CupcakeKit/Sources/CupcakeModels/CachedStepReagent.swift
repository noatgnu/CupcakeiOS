import Foundation
import SwiftData

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
