import Foundation
import SwiftData

@Model
public final class CachedTimeKeeper {
    @Attribute(.unique) public var serverID: Int64
    public var sessionClientID: UUID
    public var stepClientID: UUID?
    public var started: Bool
    public var startTime: String?
    public var currentDuration: Int
    public var originalDuration: Int

    public init(
        serverID: Int64,
        sessionClientID: UUID,
        stepClientID: UUID? = nil,
        started: Bool = false,
        startTime: String? = nil,
        currentDuration: Int,
        originalDuration: Int
    ) {
        self.serverID = serverID
        self.sessionClientID = sessionClientID
        self.stepClientID = stepClientID
        self.started = started
        self.startTime = startTime
        self.currentDuration = currentDuration
        self.originalDuration = originalDuration
    }
}
