/// `GET instrument-jobs/` response shape. Only the fields this app currently needs are modeled.
public struct InstrumentJobDTO: Decodable, Sendable {
    public let id: Int64
    public let jobName: String?
    public let jobType: String
    public let status: String
    public let project: Int64?
    public let instrument: Int64?
    public let submittedAt: String?
    public let completedAt: String?
    public let metadataTable: Int64?
    public let labGroup: Int64?
    public let staff: [Int64]
    public let staffUsernames: [String]
    public let canEditStaffOnlyColumns: Bool
    public let funder: String?
    public let costCenter: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        jobName = try container.decodeIfPresent(String.self, forKey: .jobName)
        jobType = try container.decode(String.self, forKey: .jobType)
        status = try container.decode(String.self, forKey: .status)
        project = try container.decodeIfPresent(Int64.self, forKey: .project)
        instrument = try container.decodeIfPresent(Int64.self, forKey: .instrument)
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        metadataTable = try container.decodeIfPresent(Int64.self, forKey: .metadataTable)
        labGroup = try container.decodeIfPresent(Int64.self, forKey: .labGroup)
        staff = try container.decodeIfPresent([Int64].self, forKey: .staff) ?? []
        staffUsernames = try container.decodeIfPresent([String].self, forKey: .staffUsernames) ?? []
        canEditStaffOnlyColumns = try container.decodeIfPresent(Bool.self, forKey: .canEditStaffOnlyColumns) ?? false
        funder = try container.decodeIfPresent(String.self, forKey: .funder)
        costCenter = try container.decodeIfPresent(String.self, forKey: .costCenter)
    }

    private enum CodingKeys: String, CodingKey {
        case id, jobName, jobType, status, project, instrument, submittedAt, completedAt
        case metadataTable, labGroup, staff, staffUsernames, canEditStaffOnlyColumns
        case funder, costCenter
    }
}

/// `PATCH instrument-jobs/{id}/` body for funder/cost-center (free-text fields).
public struct UpdateInstrumentJobFunderCostCenterRequest: Encodable, Sendable {
    public var funder: String?
    public var costCenter: String?

    public init(funder: String?, costCenter: String?) {
        self.funder = funder
        self.costCenter = costCenter
    }
}

/// `PATCH instrument-jobs/{id}/` body for lab group assignment, not part of the initial create call.
public struct UpdateInstrumentJobLabGroupRequest: Encodable, Sendable {
    public var labGroup: Int64

    public init(labGroup: Int64) {
        self.labGroup = labGroup
    }
}

/// `PATCH instrument-jobs/{id}/` body for assigning the booked instrument, required for the metadata-merge signal to fire.
public struct UpdateInstrumentJobInstrumentRequest: Encodable, Sendable {
    public var instrument: Int64

    public init(instrument: Int64) {
        self.instrument = instrument
    }
}

/// `PATCH instrument-jobs/{id}/` body for staff assignment. Rejects with a 400 naming any user who isn't a direct, process-jobs-enabled lab-group member.
public struct UpdateInstrumentJobStaffRequest: Encodable, Sendable {
    public var staff: [Int64]

    public init(staff: [Int64]) {
        self.staff = staff
    }
}

/// `POST instrument-jobs/` body. Every other field (lab group, staff, etc.) is a separate PATCH after this.
public struct CreateInstrumentJobRequest: Encodable, Sendable {
    public var jobType: String
    public var jobName: String?
    public var project: Int64?

    public init(jobType: String = "analysis", jobName: String?, project: Int64?) {
        self.jobType = jobType
        self.jobName = jobName
        self.project = project
    }
}

public struct ProjectColumnValuesResponse: Decodable, Sendable {
    public let values: [String]
}
