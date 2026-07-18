import Foundation
import SwiftData

@Model
public final class CachedInstrumentJob {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var jobName: String?
    public var jobType: String
    public var status: String
    public var projectClientID: UUID?
    public var instrumentServerID: Int64?
    public var submittedAt: String?
    public var completedAt: String?
    public var metadataTableServerID: Int64?
    public var labGroupServerID: Int64?
    public var staffServerIDs: [Int64]
    public var staffUsernames: [String]
    public var canEditStaffOnlyColumns: Bool
    public var funder: String?
    public var costCenter: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var ownerServerID: Int64?
    public var ownerUsername: String?

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        jobName: String? = nil,
        jobType: String = "analysis",
        status: String = "draft",
        projectClientID: UUID? = nil,
        instrumentServerID: Int64? = nil,
        submittedAt: String? = nil,
        completedAt: String? = nil,
        metadataTableServerID: Int64? = nil,
        labGroupServerID: Int64? = nil,
        staffServerIDs: [Int64] = [],
        staffUsernames: [String] = [],
        canEditStaffOnlyColumns: Bool = false,
        funder: String? = nil,
        costCenter: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        ownerServerID: Int64? = nil,
        ownerUsername: String? = nil
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.jobName = jobName
        self.jobType = jobType
        self.status = status
        self.projectClientID = projectClientID
        self.instrumentServerID = instrumentServerID
        self.submittedAt = submittedAt
        self.completedAt = completedAt
        self.metadataTableServerID = metadataTableServerID
        self.labGroupServerID = labGroupServerID
        self.staffServerIDs = staffServerIDs
        self.staffUsernames = staffUsernames
        self.canEditStaffOnlyColumns = canEditStaffOnlyColumns
        self.funder = funder
        self.costCenter = costCenter
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ownerServerID = ownerServerID
        self.ownerUsername = ownerUsername
    }
}
