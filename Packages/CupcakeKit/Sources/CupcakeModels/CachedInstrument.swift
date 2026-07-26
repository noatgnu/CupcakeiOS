import Foundation
import SwiftData

@Model
public final class CachedInstrument {
    @Attribute(.unique) public var serverID: Int64
    public var instrumentName: String
    public var instrumentDescription: String?
    public var enabled: Bool
    public var acceptsBookings: Bool
    public var allowOverlappingBookings: Bool
    public var maintenanceOverdue: Bool
    public var metadataTableServerID: Int64?
    public var ownerServerID: Int64?
    public var isVaulted: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        serverID: Int64,
        instrumentName: String,
        instrumentDescription: String? = nil,
        enabled: Bool,
        acceptsBookings: Bool,
        allowOverlappingBookings: Bool,
        maintenanceOverdue: Bool,
        metadataTableServerID: Int64? = nil,
        ownerServerID: Int64? = nil,
        isVaulted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.serverID = serverID
        self.instrumentName = instrumentName
        self.instrumentDescription = instrumentDescription
        self.enabled = enabled
        self.acceptsBookings = acceptsBookings
        self.allowOverlappingBookings = allowOverlappingBookings
        self.maintenanceOverdue = maintenanceOverdue
        self.metadataTableServerID = metadataTableServerID
        self.ownerServerID = ownerServerID
        self.isVaulted = isVaulted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
