/// `GET projects/` response shape. Only the fields this app currently needs are modeled.
public struct ProjectDTO: Decodable, Sendable {
    public let id: Int64
    public let projectName: String
    public let projectDescription: String?
}

/// `POST projects/` body. `owner` is force-set server-side, so it's not included here.
public struct CreateProjectRequest: Encodable, Sendable {
    public var projectName: String
    public var projectDescription: String?

    public init(projectName: String, projectDescription: String? = nil) {
        self.projectName = projectName
        self.projectDescription = projectDescription
    }
}

/// `PATCH projects/{id}/` body.
public struct UpdateProjectRequest: Encodable, Sendable {
    public var projectName: String
    public var projectDescription: String?

    public init(projectName: String, projectDescription: String? = nil) {
        self.projectName = projectName
        self.projectDescription = projectDescription
    }
}
