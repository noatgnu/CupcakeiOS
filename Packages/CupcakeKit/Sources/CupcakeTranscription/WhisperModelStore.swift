import Foundation
import WhisperKit

public enum WhisperModelStore {
    private static let activeModelDefaultsKey = "cupcake.whisperActiveModelVariant"
    private static let downloadedVariantsDefaultsKey = "cupcake.whisperDownloadedModelVariants"

    public static var activeModelVariant: String {
        get {
            UserDefaults.standard.string(forKey: activeModelDefaultsKey) ?? recommendedModelVariant
        }
        set {
            UserDefaults.standard.set(newValue, forKey: activeModelDefaultsKey)
        }
    }

    public static var recommendedModelVariant: String {
        WhisperKit.recommendedModels().default
    }

    public static func knownDownloadedVariants(defaults: UserDefaults = .standard) -> Set<String> {
        let stored = defaults.stringArray(forKey: downloadedVariantsDefaultsKey) ?? []
        return Set(stored)
    }

    public static var knownDownloadedVariants: Set<String> {
        get { knownDownloadedVariants(defaults: .standard) }
        set { UserDefaults.standard.set(Array(newValue), forKey: downloadedVariantsDefaultsKey) }
    }

    public static func markDownloaded(_ variant: String, defaults: UserDefaults = .standard) {
        var variants = knownDownloadedVariants(defaults: defaults)
        variants.insert(variant)
        defaults.set(Array(variants), forKey: downloadedVariantsDefaultsKey)
    }

    public static func markDeleted(_ variant: String, defaults: UserDefaults = .standard) {
        var variants = knownDownloadedVariants(defaults: defaults)
        variants.remove(variant)
        defaults.set(Array(variants), forKey: downloadedVariantsDefaultsKey)
    }

    public static func fetchAvailableModelVariants() async throws -> [String] {
        try await WhisperKit.fetchAvailableModels()
    }

    public static func download(variant: String, progressCallback: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await WhisperKit.download(variant: variant, progressCallback: { progress in
            progressCallback(progress.fractionCompleted)
        })
        markDownloaded(variant)
    }
}
