/// `GET lab-groups/` response shape. Read-only — no create/edit path yet.
public struct LabGroupDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let allowProcessJobs: Bool
}

/// `GET lab-groups/{id}/members/?direct_only=true` response entry.
public struct UserDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let username: String
    public let firstName: String?
    public let lastName: String?
}

/// A per-(user, lab group) permission grant, distinct from plain membership.
public struct LabGroupPermissionDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let user: Int64
    public let userUsername: String
    public let labGroup: Int64
    public let canView: Bool
    public let canInvite: Bool
    public let canManage: Bool
    public let canProcessJobs: Bool
}

/// `POST lab-group-permissions/` body — creates a new grant for a user with no existing record.
public struct CreateLabGroupPermissionRequest: Encodable, Sendable {
    public var user: Int64
    public var labGroup: Int64
    public var canView: Bool
    public var canInvite: Bool
    public var canManage: Bool
    public var canProcessJobs: Bool

    public init(user: Int64, labGroup: Int64, canView: Bool, canInvite: Bool, canManage: Bool, canProcessJobs: Bool) {
        self.user = user
        self.labGroup = labGroup
        self.canView = canView
        self.canInvite = canInvite
        self.canManage = canManage
        self.canProcessJobs = canProcessJobs
    }
}

/// `PATCH lab-group-permissions/{id}/` body — updates an existing grant.
public struct UpdateLabGroupPermissionRequest: Encodable, Sendable {
    public var canView: Bool
    public var canInvite: Bool
    public var canManage: Bool
    public var canProcessJobs: Bool

    public init(canView: Bool, canInvite: Bool, canManage: Bool, canProcessJobs: Bool) {
        self.canView = canView
        self.canInvite = canInvite
        self.canManage = canManage
        self.canProcessJobs = canProcessJobs
    }
}
