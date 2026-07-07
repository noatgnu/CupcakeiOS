import Foundation
import SwiftData

/// A cached folder-scoped annotation, for offline browsing.
@Model
public final class CachedFolderAnnotation {
    @Attribute(.unique) public var serverID: Int64
    public var folderServerID: Int64
    public var annotationText: String
    public var annotationType: String
    public var transcribed: Bool
    public var transcription: String?
    public var language: String?
    public var translation: String?

    public init(
        serverID: Int64,
        folderServerID: Int64,
        annotationText: String,
        annotationType: String = "text",
        transcribed: Bool = false,
        transcription: String? = nil,
        language: String? = nil,
        translation: String? = nil
    ) {
        self.serverID = serverID
        self.folderServerID = folderServerID
        self.annotationText = annotationText
        self.annotationType = annotationType
        self.transcribed = transcribed
        self.transcription = transcription
        self.language = language
        self.translation = translation
    }
}
