import Foundation
import SwiftData

/// Read-only — booking instruments requires admin/staff and is rare to do offline anyway (§3).
@Model
public final class CachedInstrument {
    @Attribute(.unique) public var serverID: Int64
    public var instrumentName: String
    public var instrumentDescription: String?
    public var enabled: Bool
    public var acceptsBookings: Bool
    public var allowOverlappingBookings: Bool
    public var maintenanceOverdue: Bool

    public init(
        serverID: Int64,
        instrumentName: String,
        instrumentDescription: String? = nil,
        enabled: Bool,
        acceptsBookings: Bool,
        allowOverlappingBookings: Bool,
        maintenanceOverdue: Bool
    ) {
        self.serverID = serverID
        self.instrumentName = instrumentName
        self.instrumentDescription = instrumentDescription
        self.enabled = enabled
        self.acceptsBookings = acceptsBookings
        self.allowOverlappingBookings = allowOverlappingBookings
        self.maintenanceOverdue = maintenanceOverdue
    }
}
