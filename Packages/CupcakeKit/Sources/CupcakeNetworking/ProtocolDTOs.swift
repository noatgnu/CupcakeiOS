public struct ProtocolStepDTO: Decodable, Sendable {
    public let id: Int64
    public let stepDescription: String
    public let order: Int
    public let stepDuration: Int?
}

public struct ProtocolSectionDTO: Decodable, Sendable {
    public let id: Int64
    public let sectionDescription: String?
    public let order: Int
    public let sectionDuration: Int?
    public let steps: [ProtocolStepDTO]
}

public struct ProtocolDTO: Decodable, Sendable {
    public let id: Int64
    public let protocolTitle: String
    public let protocolDescription: String?
    public let enabled: Bool
    public let sections: [ProtocolSectionDTO]
    public let createdAt: String?
    public let updatedAt: String?
    public let owner: Int64?
    public let ownerUsername: String?
    public let editors: [Int64]
    public let editorsUsernames: [String]
    public let viewers: [Int64]
    public let viewersUsernames: [String]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        protocolTitle = try container.decode(String.self, forKey: .protocolTitle)
        protocolDescription = try container.decodeIfPresent(String.self, forKey: .protocolDescription)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        sections = try container.decodeIfPresent([ProtocolSectionDTO].self, forKey: .sections) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        owner = try container.decodeIfPresent(Int64.self, forKey: .owner)
        ownerUsername = try container.decodeIfPresent(String.self, forKey: .ownerUsername)
        editors = try container.decodeIfPresent([Int64].self, forKey: .editors) ?? []
        editorsUsernames = try container.decodeIfPresent([String].self, forKey: .editorsUsernames) ?? []
        viewers = try container.decodeIfPresent([Int64].self, forKey: .viewers) ?? []
        viewersUsernames = try container.decodeIfPresent([String].self, forKey: .viewersUsernames) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, protocolTitle, protocolDescription, enabled, sections, createdAt, updatedAt
        case owner, ownerUsername, editors, editorsUsernames, viewers, viewersUsernames
    }
}

public struct UpdateProtocolAccessRequest: Encodable, Sendable {
    public var editors: [Int64]
    public var viewers: [Int64]

    public init(editors: [Int64], viewers: [Int64]) {
        self.editors = editors
        self.viewers = viewers
    }
}

public struct CreateProtocolRequest: Encodable, Sendable {
    public var protocolTitle: String
    public var protocolDescription: String?
    public var enabled: Bool

    public init(protocolTitle: String, protocolDescription: String?, enabled: Bool) {
        self.protocolTitle = protocolTitle
        self.protocolDescription = protocolDescription
        self.enabled = enabled
    }
}

public struct UpdateProtocolRequest: Encodable, Sendable {
    public var protocolTitle: String
    public var protocolDescription: String?
    public var enabled: Bool

    public init(protocolTitle: String, protocolDescription: String?, enabled: Bool) {
        self.protocolTitle = protocolTitle
        self.protocolDescription = protocolDescription
        self.enabled = enabled
    }
}

public struct CreateProtocolSectionRequest: Encodable, Sendable {
    public var protocol_: Int64
    public var sectionDescription: String?
    public var sectionDuration: Int?
    public var order: Int

    enum CodingKeys: String, CodingKey {
        case protocol_ = "protocol"
        case sectionDescription, sectionDuration, order
    }

    public init(protocolServerID: Int64, sectionDescription: String?, sectionDuration: Int?, order: Int) {
        self.protocol_ = protocolServerID
        self.sectionDescription = sectionDescription
        self.sectionDuration = sectionDuration
        self.order = order
    }
}

public struct UpdateProtocolSectionRequest: Encodable, Sendable {
    public var sectionDescription: String?
    public var sectionDuration: Int?

    public init(sectionDescription: String?, sectionDuration: Int?) {
        self.sectionDescription = sectionDescription
        self.sectionDuration = sectionDuration
    }
}

public struct CreateProtocolStepRequest: Encodable, Sendable {
    public var protocol_: Int64
    public var stepSection: Int64
    public var stepDescription: String
    public var stepDuration: Int?
    public var order: Int

    enum CodingKeys: String, CodingKey {
        case protocol_ = "protocol"
        case stepSection, stepDescription, stepDuration, order
    }

    public init(protocolServerID: Int64, sectionServerID: Int64, stepDescription: String, stepDuration: Int?, order: Int) {
        self.protocol_ = protocolServerID
        self.stepSection = sectionServerID
        self.stepDescription = stepDescription
        self.stepDuration = stepDuration
        self.order = order
    }
}

public struct UpdateProtocolStepRequest: Encodable, Sendable {
    public var stepDescription: String
    public var stepDuration: Int?

    public init(stepDescription: String, stepDuration: Int?) {
        self.stepDescription = stepDescription
        self.stepDuration = stepDuration
    }
}

public struct ImportProtocolFromURLRequest: Encodable, Sendable {
    public var url: String

    public init(url: String) {
        self.url = url
    }
}

public struct ExportURLResponse: Decodable, Sendable {
    public let downloadUrl: String
}
