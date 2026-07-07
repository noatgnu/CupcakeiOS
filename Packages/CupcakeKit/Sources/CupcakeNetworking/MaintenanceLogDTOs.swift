public struct MaintenanceLogDTO: Decodable, Sendable {
    public let id: Int64
    public let instrument: Int64
    public let instrumentName: String?
    public let maintenanceDate: String?
    public let maintenanceType: String
    public let status: String
    public let maintenanceDescription: String?
    public let maintenanceNotes: String?
    public let isTemplate: Bool
}

public struct CreateMaintenanceLogRequest: Encodable, Sendable {
    public var instrument: Int64
    public var maintenanceDate: String?
    public var maintenanceType: String
    public var status: String
    public var maintenanceDescription: String?
    public var maintenanceNotes: String?

    public init(instrument: Int64, maintenanceDate: String?, maintenanceType: String, status: String, maintenanceDescription: String?, maintenanceNotes: String?) {
        self.instrument = instrument
        self.maintenanceDate = maintenanceDate
        self.maintenanceType = maintenanceType
        self.status = status
        self.maintenanceDescription = maintenanceDescription
        self.maintenanceNotes = maintenanceNotes
    }
}

public struct UpdateMaintenanceLogStatusRequest: Encodable, Sendable {
    public var status: String

    public init(status: String) {
        self.status = status
    }
}
