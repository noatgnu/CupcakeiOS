import Foundation
import SwiftData

/// Read-only after creation, via the 3-call booking flow.
@Model
public final class CachedInstrumentJobAnnotation {
    @Attribute(.unique) public var serverID: Int64
    /// The parent job's `clientID`, resolved at upsert time.
    public var instrumentJobClientID: UUID
    public var annotationText: String?
    public var annotationType: String?
    public var role: String
    public var order: Int
    /// Set once the `InstrumentUsageJobAnnotation` link succeeds.
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
