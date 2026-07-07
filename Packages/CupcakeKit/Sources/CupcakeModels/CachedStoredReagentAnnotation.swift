import Foundation
import SwiftData

/// A note/document attached to a stored reagent, filed into a predefined folder. Server-ID-keyed, online-only.
@Model
public final class CachedStoredReagentAnnotation {
    @Attribute(.unique) public var serverID: Int64
    public var storedReagentServerID: Int64
    public var folderServerID: Int64
    public var folderName: String
    public var annotationText: String
    public var annotationType: String
    public var scratched: Bool

    public init(
        serverID: Int64,
        storedReagentServerID: Int64,
        folderServerID: Int64,
        folderName: String,
        annotationText: String,
        annotationType: String,
        scratched: Bool = false
    ) {
        self.serverID = serverID
        self.storedReagentServerID = storedReagentServerID
        self.folderServerID = folderServerID
        self.folderName = folderName
        self.annotationText = annotationText
        self.annotationType = annotationType
        self.scratched = scratched
    }
}
