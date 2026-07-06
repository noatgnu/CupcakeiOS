import Foundation
import SwiftData

/// Read-only after creation in this app's v1 slice — created via the 3-call booking flow
/// (`InstrumentJobAnnotationSyncService.createBookingAnnotation`), never edited locally.
@Model
public final class CachedInstrumentJobAnnotation {
    @Attribute(.unique) public var serverID: Int64
    /// The parent job's `clientID`, resolved at upsert time — mirrors every other
    /// not-yet-synced-parent reference in this app (though in practice a job must already be
    /// synced before this can be created at all, since the booking-merge flow is online-only).
    public var instrumentJobClientID: UUID
    public var annotationText: String?
    public var annotationType: String?
    public var role: String
    public var order: Int
    /// Set once the `InstrumentUsageJobAnnotation` link succeeds — lets the UI show which
    /// booking (instrument/time range) this annotation refers to via `CachedInstrumentUsage`.
    public var instrumentUsageServerID: Int64?

    public init(
        serverID: Int64,
        instrumentJobClientID: UUID,
        annotationText: String? = nil,
        annotationType: String? = nil,
        role: String = "user",
        order: Int = 0,
        instrumentUsageServerID: Int64? = nil
    ) {
        self.serverID = serverID
        self.instrumentJobClientID = instrumentJobClientID
        self.annotationText = annotationText
        self.annotationType = annotationType
        self.role = role
        self.order = order
        self.instrumentUsageServerID = instrumentUsageServerID
    }
}
