public struct StepReagentDTO: Decodable, Sendable {
    public let id: Int64
    public let step: Int64
    public let reagent: ReagentDTO
    public let quantity: Double
    public let scalable: Bool
    public let scalableFactor: Double
}

public struct CreateReagentRequest: Encodable, Sendable {
    public var name: String
    public var unit: String

    public init(name: String, unit: String) {
        self.name = name
        self.unit = unit
    }
}

public struct CreateStepReagentRequest: Encodable, Sendable {
    public var step: Int64
    public var reagentId: Int64
    public var quantity: Double
    public var scalable: Bool
    public var scalableFactor: Double

    public init(step: Int64, reagentId: Int64, quantity: Double, scalable: Bool, scalableFactor: Double) {
        self.step = step
        self.reagentId = reagentId
        self.quantity = quantity
        self.scalable = scalable
        self.scalableFactor = scalableFactor
    }
}

public struct UpdateStepReagentRequest: Encodable, Sendable {
    public var quantity: Double
    public var scalable: Bool
    public var scalableFactor: Double

    public init(quantity: Double, scalable: Bool, scalableFactor: Double) {
        self.quantity = quantity
        self.scalable = scalable
        self.scalableFactor = scalableFactor
    }
}
