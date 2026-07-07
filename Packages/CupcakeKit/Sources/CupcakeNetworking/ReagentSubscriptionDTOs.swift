public struct ReagentSubscriptionDTO: Decodable, Sendable {
    public let id: Int64
    public let user: Int64
    public let storedReagent: Int64
    public let notifyOnLowStock: Bool
    public let notifyOnExpiry: Bool
}

public struct CreateReagentSubscriptionRequest: Encodable, Sendable {
    public var user: Int64
    public var storedReagent: Int64
    public var notifyOnLowStock: Bool
    public var notifyOnExpiry: Bool

    public init(user: Int64, storedReagent: Int64, notifyOnLowStock: Bool, notifyOnExpiry: Bool) {
        self.user = user
        self.storedReagent = storedReagent
        self.notifyOnLowStock = notifyOnLowStock
        self.notifyOnExpiry = notifyOnExpiry
    }
}

public struct UpdateReagentSubscriptionRequest: Encodable, Sendable {
    public var notifyOnLowStock: Bool
    public var notifyOnExpiry: Bool

    public init(notifyOnLowStock: Bool, notifyOnExpiry: Bool) {
        self.notifyOnLowStock = notifyOnLowStock
        self.notifyOnExpiry = notifyOnExpiry
    }
}
