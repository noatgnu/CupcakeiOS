/// `GET instruments/` response shape.
public struct InstrumentDTO: Decodable, Sendable {
    public let id: Int64
    public let instrumentName: String
    public let instrumentDescription: String?
    public let enabled: Bool
    public let acceptsBookings: Bool
    public let allowOverlappingBookings: Bool
    public let maintenanceOverdue: Bool
}

/// `POST instruments/` body. Requires `is_staff`/`is_superuser` server-side.
public struct CreateInstrumentRequest: Encodable, Sendable {
    public var instrumentName: String
    public var instrumentDescription: String?
    public var enabled: Bool
    public var acceptsBookings: Bool
    public var allowOverlappingBookings: Bool

    public init(instrumentName: String, instrumentDescription: String? = nil, enabled: Bool, acceptsBookings: Bool, allowOverlappingBookings: Bool) {
        self.instrumentName = instrumentName
        self.instrumentDescription = instrumentDescription
        self.enabled = enabled
        self.acceptsBookings = acceptsBookings
        self.allowOverlappingBookings = allowOverlappingBookings
    }
}

/// `PATCH instruments/{id}/` body — same staff/superuser requirement as create.
public struct UpdateInstrumentRequest: Encodable, Sendable {
    public var instrumentName: String
    public var instrumentDescription: String?
    public var enabled: Bool
    public var acceptsBookings: Bool
    public var allowOverlappingBookings: Bool

    public init(instrumentName: String, instrumentDescription: String? = nil, enabled: Bool, acceptsBookings: Bool, allowOverlappingBookings: Bool) {
        self.instrumentName = instrumentName
        self.instrumentDescription = instrumentDescription
        self.enabled = enabled
        self.acceptsBookings = acceptsBookings
        self.allowOverlappingBookings = allowOverlappingBookings
    }
}

/// `usageHours` is a `DecimalField`, serialized by DRF as a string, not a bare JSON number.
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

/// `POST instrument-usage/` body. `approved` is deliberately never sent; the server decides it conditionally.
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
