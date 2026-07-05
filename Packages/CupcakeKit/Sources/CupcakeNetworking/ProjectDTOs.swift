/// Field names verified directly against `ccrv/serializers.py`'s `ProjectSerializer`/
/// `ProjectCreateSerializer` and the `Project`/`AbstractResource` models (`ccrv/models.py:25-46`,
/// `ccc/models.py:163-197`). Only the fields this app's v1 Job-slice actually needs are modeled
/// — `ownerUsername`/`labGroup`/`visibility`/`isVaulted` etc. exist server-side but aren't
/// surfaced here yet.
public struct ProjectDTO: Decodable, Sendable {
    public let id: Int64
    public let projectName: String
    public let projectDescription: String?
}

/// `POST projects/` body. `owner` is force-set server-side from the requesting user regardless
/// of what's sent (`ProjectCreateSerializer.create()`, `ccrv/serializers.py:612-615`), so it's
/// not included here.
public struct CreateProjectRequest: Encodable, Sendable {
    public var projectName: String
    public var projectDescription: String?

    public init(projectName: String, projectDescription: String? = nil) {
        self.projectName = projectName
        self.projectDescription = projectDescription
    }
}
