public struct ProjectDTO: Decodable, Sendable {
    public let id: Int64
    public let projectName: String
    public let projectDescription: String?
    public let createdAt: String?
    public let updatedAt: String?
}

public struct CreateProjectRequest: Encodable, Sendable {
    public var projectName: String
    public var projectDescription: String?

    public init(projectName: String, projectDescription: String? = nil) {
        self.projectName = projectName
        self.projectDescription = projectDescription
    }
}

public struct UpdateProjectRequest: Encodable, Sendable {
    public var projectName: String
    public var projectDescription: String?

    public init(projectName: String, projectDescription: String? = nil) {
        self.projectName = projectName
        self.projectDescription = projectDescription
    }
}
