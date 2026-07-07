/// `GET steps/` response shape. `stepDuration` is in seconds, not minutes.
public struct ProtocolStepDTO: Decodable, Sendable {
    public let id: Int64
    public let stepDescription: String
    public let order: Int
    public let stepDuration: Int?
}

/// `sectionDuration` (seconds) — same provenance as `ProtocolStepDTO.stepDuration`.
public struct ProtocolSectionDTO: Decodable, Sendable {
    public let id: Int64
    public let sectionDescription: String?
    public let order: Int
    public let sectionDuration: Int?
    public let steps: [ProtocolStepDTO]
}

/// `sections` is absent entirely from `POST protocols/`'s create response; defaults to `[]` when absent.
public struct ProtocolDTO: Decodable, Sendable {
    public let id: Int64
    public let protocolTitle: String
    public let protocolDescription: String?
    public let enabled: Bool
    public let sections: [ProtocolSectionDTO]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        protocolTitle = try container.decode(String.self, forKey: .protocolTitle)
        protocolDescription = try container.decodeIfPresent(String.self, forKey: .protocolDescription)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        sections = try container.decodeIfPresent([ProtocolSectionDTO].self, forKey: .sections) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, protocolTitle, protocolDescription, enabled, sections
    }
}

/// `POST protocols/` body. `owner` is server-assigned. `enabled` means "public," not soft-delete.
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

/// `PATCH protocols/{id}/` body.
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

/// `POST sections/` body. `order` is not server-auto-incremented; the caller must supply the next value.
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

/// `PATCH sections/{id}/` body.
public struct UpdateProtocolSectionRequest: Encodable, Sendable {
    public var sectionDescription: String?
    public var sectionDuration: Int?

    public init(sectionDescription: String?, sectionDuration: Int?) {
        self.sectionDescription = sectionDescription
        self.sectionDuration = sectionDuration
    }
}

/// `POST steps/` body. A step requires both a `protocol` FK and a `step_section` FK.
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

/// `PATCH steps/{id}/` body.
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
