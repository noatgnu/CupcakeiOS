import Foundation
import SwiftData

@Model
public final class OutboxEntry {
    @Attribute(.unique) public var id: UUID
    public var operationType: String
    public var payloadJSON: Data
    public var relatedClientID: UUID
    public var status: String
    public var retryCount: Int
    public var lastError: String?
    public var createdAt: Date
    public var sequence: Int

    public init(
        id: UUID = UUID(),
        operationType: String,
        payloadJSON: Data,
        relatedClientID: UUID,
        status: String = OutboxEntryStatus.pending.rawValue,
        retryCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        sequence: Int = 0
    ) {
        self.id = id
        self.operationType = operationType
        self.payloadJSON = payloadJSON
        self.relatedClientID = relatedClientID
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.sequence = sequence
    }
}

public enum OutboxEntryStatus: String, Sendable {
    case pending
    case failed
}

public enum OutboxOperationType: String, Sendable {
    case createProtocol
    case createSection
    case createStep
    case createSession
    case createStepReagent
    case createTextAnnotation
    case createStoredReagent
    case createReagentAction
    case createInstrumentUsage
    case createProject
    case createInstrumentJob
    case createStepAudioAnnotation
    case createSessionAudioAnnotation
    case createStepImageAnnotation
    case createSessionImageAnnotation
    case createStepVideoAnnotation
    case createSessionVideoAnnotation
    case createStepSketchAnnotation
    case createSessionSketchAnnotation
}

public struct CreateProtocolPayload: Codable, Sendable {
    public var title: String
    public var description: String?
    public var enabled: Bool

    public init(title: String, description: String?, enabled: Bool) {
        self.title = title
        self.description = description
        self.enabled = enabled
    }
}

public struct EmptyOutboxPayload: Codable, Sendable {
    public init() {}
}
