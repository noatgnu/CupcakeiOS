import Foundation
import Testing

@testable import CupcakeTranscription

@Suite("WhisperModelStore")
struct WhisperModelStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "WhisperModelStoreTests-\(UUID().uuidString)")!
    }

    @Test("markDownloaded/markDeleted round-trip through knownDownloadedVariants")
    func markDownloadedAndDeletedRoundTrip() {
        let defaults = makeDefaults()
        #expect(WhisperModelStore.knownDownloadedVariants(defaults: defaults).isEmpty)

        WhisperModelStore.markDownloaded("tiny.en", defaults: defaults)
        WhisperModelStore.markDownloaded("base", defaults: defaults)
        #expect(WhisperModelStore.knownDownloadedVariants(defaults: defaults) == ["tiny.en", "base"])

        WhisperModelStore.markDeleted("tiny.en", defaults: defaults)
        #expect(WhisperModelStore.knownDownloadedVariants(defaults: defaults) == ["base"])
    }

    @Test("markDownloaded is idempotent for the same variant")
    func markDownloadedIdempotent() {
        let defaults = makeDefaults()
        WhisperModelStore.markDownloaded("small", defaults: defaults)
        WhisperModelStore.markDownloaded("small", defaults: defaults)
        #expect(WhisperModelStore.knownDownloadedVariants(defaults: defaults) == ["small"])
    }

    @Test("markDeleted on a variant that was never downloaded is a no-op")
    func markDeletedNoOpWhenAbsent() {
        let defaults = makeDefaults()
        WhisperModelStore.markDownloaded("tiny", defaults: defaults)
        WhisperModelStore.markDeleted("large-v3", defaults: defaults)
        #expect(WhisperModelStore.knownDownloadedVariants(defaults: defaults) == ["tiny"])
    }
}
