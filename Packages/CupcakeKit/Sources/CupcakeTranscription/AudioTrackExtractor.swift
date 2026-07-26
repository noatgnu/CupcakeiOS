import AVFoundation
import Foundation

public enum AudioTrackExtractionError: Error {
    case exportSessionCreationFailed
    case exportFailed
}

public enum AudioTrackExtractor {
    private static let audioContainerExtensions: Set<String> = ["wav", "mp3", "m4a", "flac", "caf", "aiff"]

    public static func isAudioContainer(fileURL: URL) -> Bool {
        audioContainerExtensions.contains(fileURL.pathExtension.lowercased())
    }

    public static func extractAudioTrack(from fileURL: URL) async throws -> URL {
        guard !isAudioContainer(fileURL: fileURL) else {
            return fileURL
        }

        let asset = AVURLAsset(url: fileURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioTrackExtractionError.exportSessionCreationFailed
        }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try? FileManager.default.removeItem(at: outputURL)

        try await exportSession.export(to: outputURL, as: .m4a)
        return outputURL
    }
}
