import Foundation
import SwiftData

@Model
public final class CachedLabGroup {
    @Attribute(.unique) public var serverID: Int64
    public var name: String
    public var groupDescription: String?
    public var parentGroupServerID: Int64?
    public var fullPathNames: [String]
    public var creatorServerID: Int64?
    public var creatorName: String?
    public var isActive: Bool
    public var allowMemberInvites: Bool
    public var allowProcessJobs: Bool
    public var memberCount: Int
    public var subGroupsCount: Int
    public var isCreator: Bool
    public var isMember: Bool
    public var canInvite: Bool
    public var canManage: Bool
    public var canProcessJobs: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        serverID: Int64,
        name: String,
        groupDescription: String? = nil,
        parentGroupServerID: Int64? = nil,
        fullPathNames: [String] = [],
        creatorServerID: Int64? = nil,
        creatorName: String? = nil,
        isActive: Bool = true,
        allowMemberInvites: Bool = true,
        allowProcessJobs: Bool = false,
        memberCount: Int = 0,
        subGroupsCount: Int = 0,
        isCreator: Bool = false,
        isMember: Bool = false,
        canInvite: Bool = false,
        canManage: Bool = false,
        canProcessJobs: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.serverID = serverID
        self.name = name
        self.groupDescription = groupDescription
        self.parentGroupServerID = parentGroupServerID
        self.fullPathNames = fullPathNames
        self.creatorServerID = creatorServerID
        self.creatorName = creatorName
        self.isActive = isActive
        self.allowMemberInvites = allowMemberInvites
        self.allowProcessJobs = allowProcessJobs
        self.memberCount = memberCount
        self.subGroupsCount = subGroupsCount
        self.isCreator = isCreator
        self.isMember = isMember
        self.canInvite = canInvite
        self.canManage = canManage
        self.canProcessJobs = canProcessJobs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
