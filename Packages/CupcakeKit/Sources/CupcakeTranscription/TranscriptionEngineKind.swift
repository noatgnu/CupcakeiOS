import Foundation

public enum TranscriptionEngineKind: String, CaseIterable, Sendable, Identifiable {
    case apple
    case whisperKit

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .apple: "Apple"
        case .whisperKit: "WhisperKit"
        }
    }
}

public enum TranscriptionEngineFactory {
    private static let engineKindDefaultsKey = "cupcake.transcriptionEngineKind"

    public static var selectedEngineKind: TranscriptionEngineKind {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: engineKindDefaultsKey),
                  let kind = TranscriptionEngineKind(rawValue: rawValue) else {
                return .apple
            }
            return kind
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: engineKindDefaultsKey)
        }
    }

    private nonisolated(unsafe) static var cachedEngine: (any TranscriptionEngine)?
    private nonisolated(unsafe) static var cachedEngineKey: String?

    public static func makeEngine(kind: TranscriptionEngineKind = TranscriptionEngineFactory.selectedEngineKind) -> any TranscriptionEngine {
        let key = kind == .whisperKit ? "whisperKit:\(WhisperModelStore.activeModelVariant)" : "apple"
        if let cachedEngine, cachedEngineKey == key {
            return cachedEngine
        }
        let engine: any TranscriptionEngine
        switch kind {
        case .apple:
            engine = AppleSpeechTranscriptionEngine()
        case .whisperKit:
            engine = WhisperKitTranscriptionEngine(modelVariant: WhisperModelStore.activeModelVariant)
        }
        cachedEngine = engine
        cachedEngineKey = key
        return engine
    }
}
