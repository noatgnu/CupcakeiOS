import Foundation
import SwiftData

/// A cached step-level annotation.
@Model
public final class CachedStepAnnotation {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var sessionClientID: UUID
    public var stepClientID: UUID
    public var annotationText: String
    public var annotationType: String
    public var order: Int
    public var transcription: String?
    public var language: String?
    public var translation: String?
    public var pendingFileName: String?
    public var scratched: Bool
    public var instrumentUsageServerID: Int64?
    public var createdAt: String

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        sessionClientID: UUID,
        stepClientID: UUID,
        annotationText: String,
        annotationType: String = "text",
        order: Int = 0,
        transcription: String? = nil,
        language: String? = nil,
        translation: String? = nil,
        pendingFileName: String? = nil,
        scratched: Bool = false,
        instrumentUsageServerID: Int64? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.sessionClientID = sessionClientID
        self.stepClientID = stepClientID
        self.annotationText = annotationText
        self.annotationType = annotationType
        self.order = order
        self.transcription = transcription
        self.language = language
        self.translation = translation
        self.pendingFileName = pendingFileName
        self.scratched = scratched
        self.instrumentUsageServerID = instrumentUsageServerID
        self.createdAt = createdAt
    }
}
