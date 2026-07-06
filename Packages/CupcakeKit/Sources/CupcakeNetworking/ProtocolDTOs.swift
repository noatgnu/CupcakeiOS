/// Field names verified directly against `ccrv/serializers.py`'s `ProtocolStepSerializer`.
/// Note the model's real Django primary key is `id` — `protocol_id` (on `ProtocolDTO` only) is a
/// separate, nullable field used for protocols.io interop, not this app's identity.
/// `stepDuration` (**seconds**, not minutes — verified against the reference web app's
/// `duration-input.ts`, which decomposes this value into day/hour/min/sec sub-fields) is a real,
/// populated field for protocols.io-imported protocols — `create_protocol_from_url()`
/// (`ccrv/models.py:148-219`) sets it from the source step's own `duration`, so it's part of the
/// genuine protocol-templating structure, not a vestigial field.
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

/// `sections` is absent entirely from `POST protocols/`'s create response (`ProtocolModelCreateSerializer`
/// doesn't include it — only the list/retrieve serializer does) — confirmed live: decoding a real
/// create response with `sections` declared non-optional threw `DecodingError.keyNotFound` on
/// every single protocol creation, the create call never actually completing as far as the client
/// was concerned even though the server had already made it. Defaults to `[]` when absent rather
/// than being `Optional`, since "no sections yet" and "sections not decoded" mean the same thing
/// here — every caller already treats an empty array as "no sections."
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

/// `POST protocols/` body. Field set verified against `ProtocolModelCreateSerializer`
/// (`ccrv/serializers.py:618-646`) — `owner` is server-assigned from the requesting user
/// regardless of what's sent, so it's not included here. `enabled` means "public/accessible to
/// everyone," not a soft-delete/archive flag — the reference web app's create modal always
/// sends an explicit value (default `false` there), never relies on the serializer's own default.
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

/// `POST sections/` body. Field set verified against `ProtocolSectionSerializer`
/// (`ccrv/serializers.py:243-260`) — `order` is a plain `PositiveIntegerField(default=0)`, **not**
/// server-auto-incremented on create, so the caller must supply the correct next value.
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

/// `POST steps/` body. Field set verified against `ProtocolStepSerializer`
/// (`ccrv/serializers.py:181-211`) — a step requires **both** a `protocol` FK and a `step_section`
/// FK; `step_section` is nullable at the model level, but the reference web app's own
/// `step-create-modal.ts` always supplies both together, and this app does the same (a step is
/// only ever created within a section here). `order` is not server-auto-incremented, same as
/// sections.
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
