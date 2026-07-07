import Foundation
import SwiftData

/// A cached session; `protocolClientIDs` holds its 0..N attached protocols.
@Model
public final class CachedSession {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var uniqueID: String?
    public var name: String?
    public var enabled: Bool
    /// Nullable — the server can serialize this as JSON `null` for an unstarted session.
    public var isRunning: Bool?
    public var status: String
    public var protocolServerIDs: [Int64]
    public var protocolClientIDs: [UUID]
    @available(*, deprecated, message: "Use protocolClientIDs instead — kept for one release.")
    public var primaryProtocolClientID: UUID?
    /// When this device first learned about the session; used for sorting the sessions list.
    public var createdAt: Date

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        uniqueID: String? = nil,
        name: String?,
        enabled: Bool,
        isRunning: Bool?,
        status: String,
        protocolServerIDs: [Int64] = [],
        protocolClientIDs: [UUID] = [],
        primaryProtocolClientID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.uniqueID = uniqueID
        self.name = name
        self.enabled = enabled
        self.isRunning = isRunning
        self.status = status
        self.protocolServerIDs = protocolServerIDs
        self.protocolClientIDs = protocolClientIDs
        self.primaryProtocolClientID = primaryProtocolClientID
        self.createdAt = createdAt
    }
}

extension CachedSession {
    private static let backfillDefaultsKey = "cupcake.didBackfillProtocolClientIDs"

    /// One-time migration backfilling `protocolClientIDs` from the old `primaryProtocolClientID`.
    @MainActor
    public static func backfillProtocolClientIDsIfNeeded(in modelContainer: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: backfillDefaultsKey) else { return }
        let context = ModelContext(modelContainer)
        if let sessions = try? context.fetch(FetchDescriptor<CachedSession>()) {
            for session in sessions where session.protocolClientIDs.isEmpty {
                if let primaryProtocolClientID = session.primaryProtocolClientID {
                    session.protocolClientIDs = [primaryProtocolClientID]
                }
            }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: backfillDefaultsKey)
    }
}
