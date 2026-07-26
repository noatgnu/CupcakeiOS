public struct InstrumentDTO: Decodable, Sendable {
    public let id: Int64
    public let instrumentName: String
    public let instrumentDescription: String?
    public let enabled: Bool
    public let acceptsBookings: Bool
    public let allowOverlappingBookings: Bool
    public let maintenanceOverdue: Bool
    public let metadataTableId: Int64?
    public let metadataTableName: String?
    public let user: Int64?
    public let isVaulted: Bool
    public let createdAt: String?
    public let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, instrumentName, instrumentDescription, enabled, acceptsBookings, allowOverlappingBookings
        case maintenanceOverdue, metadataTableId, metadataTableName, user, isVaulted, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        instrumentName = try container.decode(String.self, forKey: .instrumentName)
        instrumentDescription = try container.decodeIfPresent(String.self, forKey: .instrumentDescription)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        acceptsBookings = try container.decode(Bool.self, forKey: .acceptsBookings)
        allowOverlappingBookings = try container.decode(Bool.self, forKey: .allowOverlappingBookings)
        maintenanceOverdue = try container.decode(Bool.self, forKey: .maintenanceOverdue)
        metadataTableId = try container.decodeIfPresent(Int64.self, forKey: .metadataTableId)
        metadataTableName = try container.decodeIfPresent(String.self, forKey: .metadataTableName)
        user = try container.decodeIfPresent(Int64.self, forKey: .user)
        isVaulted = try container.decodeIfPresent(Bool.self, forKey: .isVaulted) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

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
