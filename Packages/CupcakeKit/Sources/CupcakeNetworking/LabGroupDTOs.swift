public struct LabGroupPathSegmentDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
}

public struct LabGroupDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let parentGroup: Int64?
    public let fullPath: [LabGroupPathSegmentDTO]
    public let creator: Int64?
    public let creatorName: String?
    public let isActive: Bool
    public let allowMemberInvites: Bool
    public let allowProcessJobs: Bool
    public let memberCount: Int
    public let subGroupsCount: Int
    public let isCreator: Bool
    public let isMember: Bool
    public let canInvite: Bool
    public let canManage: Bool
    public let canProcessJobs: Bool
    public let createdAt: String?
    public let updatedAt: String?
}

public struct CreateLabGroupRequest: Encodable, Sendable {
    public var name: String
    public var description: String?
    public var parentGroup: Int64?
    public var allowMemberInvites: Bool
    public var allowProcessJobs: Bool

    public init(name: String, description: String? = nil, parentGroup: Int64? = nil, allowMemberInvites: Bool = true, allowProcessJobs: Bool = false) {
        self.name = name
        self.description = description
        self.parentGroup = parentGroup
        self.allowMemberInvites = allowMemberInvites
        self.allowProcessJobs = allowProcessJobs
    }
}

public struct UpdateLabGroupRequest: Encodable, Sendable {
    public var name: String?
    public var description: String?
    public var allowMemberInvites: Bool?
    public var allowProcessJobs: Bool?

    public init(name: String? = nil, description: String? = nil, allowMemberInvites: Bool? = nil, allowProcessJobs: Bool? = nil) {
        self.name = name
        self.description = description
        self.allowMemberInvites = allowMemberInvites
        self.allowProcessJobs = allowProcessJobs
    }
}

public struct UserDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let username: String
    public let firstName: String?
    public let lastName: String?
}

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

public struct LabGroupInvitationDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let labGroup: Int64
    public let labGroupName: String
    public let inviter: Int64
    public let inviterName: String
    public let invitedUser: Int64?
    public let invitedEmail: String
    public let status: String
    public let message: String?
    public let expiresAt: String?
    public let respondedAt: String?
    public let canAccept: Bool
    public let createdAt: String?
    public let updatedAt: String?
}

public struct CreateLabGroupInvitationRequest: Encodable, Sendable {
    public var invitedEmail: String
    public var message: String?

    public init(invitedEmail: String, message: String? = nil) {
        self.invitedEmail = invitedEmail
        self.message = message
    }
}

public struct RemoveLabGroupMemberRequest: Encodable, Sendable {
    public var userID: Int64

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }

    public init(userID: Int64) {
        self.userID = userID
    }
}
