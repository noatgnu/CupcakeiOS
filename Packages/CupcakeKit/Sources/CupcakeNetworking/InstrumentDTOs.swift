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
