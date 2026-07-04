/// Field names verified directly against `ccrv/serializers.py`'s `StepReagentSerializer` and
/// `ccrv/models.py`'s `StepReagent` (step/reagent FKs required, quantity a required non-null
/// `FloatField`, scalable/scalable_factor non-null with defaults). On read, `reagent` is a
/// *nested* nested object (`ReagentSerializer(read_only=True)`), not a bare id — reusing
/// `ReagentDTO` here decodes it correctly; `reagent_id` is a separate write-only field for
/// create, not represented here since this DTO is read-only (local creation doesn't round-trip
/// through the network — see `CachedStepReagent`'s doc comment).
public struct StepReagentDTO: Decodable, Sendable {
    public let id: Int64
    public let step: Int64
    public let reagent: ReagentDTO
    public let quantity: Double
    public let scalable: Bool
    public let scalableFactor: Double
}

/// `POST reagents/` body — only needed when attaching a brand-new reagent that doesn't already
/// exist on the server (an existing one is referenced by id instead, see
/// `CreateStepReagentRequest`).
public struct CreateReagentRequest: Encodable, Sendable {
    public var name: String
    public var unit: String

    public init(name: String, unit: String) {
        self.name = name
        self.unit = unit
    }
}

/// `POST step-reagents/` body. Field set verified against `StepReagentSerializer`
/// (`ccrv/serializers.py:703-735`) — create accepts `reagent_id` (a write-only PK field), **not**
/// a nested `reagent` object the way the read shape (`StepReagentDTO`) has it.
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
