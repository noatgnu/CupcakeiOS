/// `GET sessions/` response shape. `isRunning` can serialize as JSON `null` for an unstarted session, and `status` is absent from the create response.
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

/// `POST sessions/` body. `owner`/`unique_id` are server-assigned.
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

/// `PATCH sessions/{id}/` body — name/visibility only.
public struct UpdateSessionRequest: Encodable, Sendable {
    public var name: String
    public var enabled: Bool

    public init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
    }
}
