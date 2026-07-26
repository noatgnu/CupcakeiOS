import Foundation

public struct SyncProgress: Equatable, Sendable {
    public enum Direction: Sendable {
        case push
        case pull
    }

    public var direction: Direction
    public var label: String

    public init(direction: Direction, label: String) {
        self.direction = direction
        self.label = label
    }
}

public extension OutboxOperationType {
    var pushDisplayLabel: String {
        switch self {
        case .createProtocol: return "protocol"
        case .createSection: return "section"
        case .createStep: return "step"
        case .createSession: return "session"
        case .createStepReagent: return "step reagent"
        case .createTextAnnotation: return "note"
        case .createStoredReagent: return "stored reagent"
        case .createReagentAction: return "reagent action"
        case .createInstrumentUsage: return "instrument booking"
        case .createProject: return "project"
        case .createInstrumentJob: return "job"
        case .createStepAudioAnnotation, .createSessionAudioAnnotation: return "audio note"
        case .createStepImageAnnotation, .createSessionImageAnnotation: return "photo note"
        case .createStepVideoAnnotation, .createSessionVideoAnnotation: return "video note"
        case .createStepSketchAnnotation, .createSessionSketchAnnotation: return "sketch note"
        }
    }
}
