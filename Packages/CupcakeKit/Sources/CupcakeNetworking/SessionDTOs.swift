public struct SessionDTO: Decodable, Sendable {
    public let id: Int64
    public let uniqueId: String
    public let name: String?
    public let enabled: Bool
    public let startedAt: String?
    public let endedAt: String?
    public let isRunning: Bool?
    public let status: String?
    public let protocols: [Int64]
}

public struct CreateSessionRequest: Encodable, Sendable {
    public var name: String
    public var enabled: Bool
    public var protocols: [Int64]

    public init(name: String, enabled: Bool = true, protocols: [Int64] = []) {
        self.name = name
        self.enabled = enabled
        self.protocols = protocols
    }
}

public struct UpdateSessionRequest: Encodable, Sendable {
    public var name: String
    public var enabled: Bool

    public init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
    }
}
