import Foundation
import SwiftData

@Model
public final class CachedInstrumentJobAnnotation {
    @Attribute(.unique) public var serverID: Int64
    public var instrumentJobClientID: UUID
    public var annotationText: String?
    public var annotationType: String?
    public var role: String
    public var order: Int
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
