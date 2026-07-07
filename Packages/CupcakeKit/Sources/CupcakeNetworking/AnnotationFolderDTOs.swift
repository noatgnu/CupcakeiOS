public struct AnnotationFolderDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let folderName: String
    public let parentFolder: Int64?
    public let fullPath: String?
    public let childFoldersCount: Int?
    public let annotationsCount: Int?
    public let canEdit: Bool
    public let canDelete: Bool

    public init(
        id: Int64,
        folderName: String,
        parentFolder: Int64?,
        fullPath: String?,
        childFoldersCount: Int?,
        annotationsCount: Int?,
        canEdit: Bool,
        canDelete: Bool
    ) {
        self.id = id
        self.folderName = folderName
        self.parentFolder = parentFolder
        self.fullPath = fullPath
        self.childFoldersCount = childFoldersCount
        self.annotationsCount = annotationsCount
        self.canEdit = canEdit
        self.canDelete = canDelete
    }
}

public struct AnnotationSummaryDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let annotation: String
    public let annotationType: String
    public let folder: Int64?
    public let transcribed: Bool
    public let transcription: String?
    public let language: String?
    public let translation: String?

    public init(
        id: Int64,
        annotation: String,
        annotationType: String,
        folder: Int64?,
        transcribed: Bool,
        transcription: String?,
        language: String?,
        translation: String?
    ) {
        self.id = id
        self.annotation = annotation
        self.annotationType = annotationType
        self.folder = folder
        self.transcribed = transcribed
        self.transcription = transcription
        self.language = language
        self.translation = translation
    }
}

public struct FolderChildrenResponse: Decodable, Sendable {
    public let folders: [AnnotationFolderDTO]
    public let annotations: [AnnotationSummaryDTO]

    public init(folders: [AnnotationFolderDTO], annotations: [AnnotationSummaryDTO]) {
        self.folders = folders
        self.annotations = annotations
    }
}

public struct SessionAnnotationFolderDTO: Decodable, Sendable {
    public let id: Int64
    public let session: Int64
    public let folder: Int64
}

public struct CreateAnnotationFolderRequest: Encodable, Sendable {
    public var folderName: String
    public var parentFolder: Int64?

    public init(folderName: String, parentFolder: Int64? = nil) {
        self.folderName = folderName
        self.parentFolder = parentFolder
    }
}

public struct AttachSessionAnnotationFolderRequest: Encodable, Sendable {
    public var session: Int64
    public var folder: Int64

    public init(session: Int64, folder: Int64) {
        self.session = session
        self.folder = folder
    }
}

public struct CreateFolderAnnotationRequest: Encodable, Sendable {
    public var annotation: String
    public var annotationType: String
    public var folder: Int64

    public init(annotation: String, annotationType: String = "text", folder: Int64) {
        self.annotation = annotation
        self.annotationType = annotationType
        self.folder = folder
    }
}

public struct RenameAnnotationFolderRequest: Encodable, Sendable {
    public var folderName: String

    public init(folderName: String) {
        self.folderName = folderName
    }
}

public struct MoveAnnotationFolderRequest: Encodable, Sendable {
    public var parentFolder: Int64?

    public init(parentFolder: Int64?) {
        self.parentFolder = parentFolder
    }
}
