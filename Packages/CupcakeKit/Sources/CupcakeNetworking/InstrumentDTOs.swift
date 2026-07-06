/// Field names verified directly against `ccm/serializers.py`'s `InstrumentSerializer`/
/// `InstrumentUsageSerializer`. Endpoint paths verified against `ccm/urls.py`: `instruments/`
/// and `instrument-usage/` — the latter is singular, no trailing `s`.
public struct InstrumentDTO: Decodable, Sendable {
    public let id: Int64
    public let instrumentName: String
    public let instrumentDescription: String?
    public let enabled: Bool
    public let acceptsBookings: Bool
    public let allowOverlappingBookings: Bool
    public let maintenanceOverdue: Bool
}

/// `timeStarted`/`timeEnded` are nullable `DateTimeField`s server-side. `usageHours` is a
/// `DecimalField`, which DRF serializes as a string, not a bare JSON number — same reasoning as
/// `StoredReagentDTO.molecularWeight`'s omission.
public struct InstrumentUsageDTO: Decodable, Sendable {
    public let id: Int64
    public let instrument: Int64
    public let instrumentName: String
    public let timeStarted: String?
    public let timeEnded: String?
    public let usageHours: String?
    public let description: String
    public let approved: Bool
    public let maintenance: Bool
}

/// `POST instrument-usage/` body. Field set verified against `InstrumentUsageSerializer`
/// (`ccm/serializers.py:418-453`) and the reference web app's `instrument-usage-modal.ts`, which
/// only ever collects `timeStarted`/`timeEnded`/`description`/`maintenance` — `approved` is
/// deliberately never sent by this app. The server's real behavior when it's omitted (confirmed
/// live, correcting an earlier, incomplete assumption here) is conditional, not a flat default:
/// `ccm/serializers.py:532-536` sets `approved = False` only when the booking *requires*
/// pre-approval; when it doesn't (the common case for an instrument with no
/// `max_days_ahead_pre_approval`/`max_days_within_usage_pre_approval` restrictions — e.g. every
/// booking against a real, freshly-seeded test instrument came back `"approved": true` despite
/// never sending the field), the server auto-approves it. A client claiming its own booking is
/// pre-approved would still be wrong to do even where the backend doesn't stop it — see
/// `InstrumentSyncService`'s doc comment). Both timestamps are ISO 8601 strings; `timeEnded` is
/// nil for an in-progress booking.
public struct CreateInstrumentUsageRequest: Encodable, Sendable {
    public var instrument: Int64
    public var timeStarted: String
    public var timeEnded: String?
    public var description: String
    public var maintenance: Bool

    public init(instrument: Int64, timeStarted: String, timeEnded: String?, description: String, maintenance: Bool) {
        self.instrument = instrument
        self.timeStarted = timeStarted
        self.timeEnded = timeEnded
        self.description = description
        self.maintenance = maintenance
    }
}
