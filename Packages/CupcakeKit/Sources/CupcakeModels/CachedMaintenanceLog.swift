import Foundation
import SwiftData

/// A maintenance record for an instrument. Server-ID-keyed, online-only (requires `can_manage`).
@Model
public final class CachedMaintenanceLog {
    @Attribute(.unique) public var serverID: Int64
    public var instrumentServerID: Int64
    public var instrumentName: String
    public var maintenanceDate: String?
    public var maintenanceType: String
    public var status: String
    public var maintenanceDescription: String?
    public var maintenanceNotes: String?
    public var isTemplate: Bool

    public init(
        serverID: Int64,
        instrumentServerID: Int64,
        instrumentName: String,
        maintenanceDate: String? = nil,
        maintenanceType: String = "routine",
        status: String = "pending",
        maintenanceDescription: String? = nil,
        maintenanceNotes: String? = nil,
        isTemplate: Bool = false
    ) {
        self.serverID = serverID
        self.instrumentServerID = instrumentServerID
        self.instrumentName = instrumentName
        self.maintenanceDate = maintenanceDate
        self.maintenanceType = maintenanceType
        self.status = status
        self.maintenanceDescription = maintenanceDescription
        self.maintenanceNotes = maintenanceNotes
        self.isTemplate = isTemplate
    }
}
