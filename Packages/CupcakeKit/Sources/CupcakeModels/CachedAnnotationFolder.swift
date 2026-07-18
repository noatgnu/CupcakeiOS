import Foundation
import SwiftData

@Model
public final class CachedAnnotationFolder {
    @Attribute(.unique) public var serverID: Int64
    public var folderName: String
    public var parentFolderServerID: Int64?
    public var sessionServerID: Int64?
    public var childFoldersCount: Int
    public var annotationsCount: Int
    public var canEdit: Bool
    public var canDelete: Bool

    public init(
        serverID: Int64,
        folderName: String,
        parentFolderServerID: Int64? = nil,
        sessionServerID: Int64? = nil,
        childFoldersCount: Int = 0,
        annotationsCount: Int = 0,
        canEdit: Bool = false,
        canDelete: Bool = false
    ) {
        self.serverID = serverID
        self.folderName = folderName
        self.parentFolderServerID = parentFolderServerID
        self.sessionServerID = sessionServerID
        self.childFoldersCount = childFoldersCount
        self.annotationsCount = annotationsCount
        self.canEdit = canEdit
        self.canDelete = canDelete
    }
}
