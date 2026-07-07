public struct TimeKeeperDTO: Decodable, Sendable {
    public let id: Int64
    public let session: Int64
    public let step: Int64?
    public let started: Bool
    public let startTime: String?
    public let currentDuration: Int
    public let originalDuration: Int
}

public struct CreateTimeKeeperRequest: Encodable, Sendable {
    public var session: Int64
    public var step: Int64?
    public var currentDuration: Int
    public var originalDuration: Int

    public init(session: Int64, step: Int64?, currentDuration: Int, originalDuration: Int) {
        self.session = session
        self.step = step
        self.currentDuration = currentDuration
        self.originalDuration = originalDuration
    }
}

public struct TimeKeeperActionResponse: Decodable, Sendable {
    public let timeKeeper: TimeKeeperDTO
}
