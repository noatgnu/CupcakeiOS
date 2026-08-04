public struct SessionDTO: Decodable, Sendable {
    public let id: Int64
    public let uniqueId: String
    public let name: String?
    public let enabled: Bool
    public let startedAt: String?
    public let endedAt: String?
    public let isRunning: Bool?
    public let status: String?
    public let protocols: [Int64]
    public let createdAt: String?
    public let owner: Int64?
    public let ownerUsername: String?
    public let editors: [Int64]
    public let editorsUsernames: [String]
    public let viewers: [Int64]
    public let viewersUsernames: [String]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        protocols = try container.decodeIfPresent([Int64].self, forKey: .protocols) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        owner = try container.decodeIfPresent(Int64.self, forKey: .owner)
        ownerUsername = try container.decodeIfPresent(String.self, forKey: .ownerUsername)
        editors = try container.decodeIfPresent([Int64].self, forKey: .editors) ?? []
        editorsUsernames = try container.decodeIfPresent([String].self, forKey: .editorsUsernames) ?? []
        viewers = try container.decodeIfPresent([Int64].self, forKey: .viewers) ?? []
        viewersUsernames = try container.decodeIfPresent([String].self, forKey: .viewersUsernames) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, uniqueId, name, enabled, startedAt, endedAt, isRunning, status, protocols, createdAt
        case owner, ownerUsername, editors, editorsUsernames, viewers, viewersUsernames
    }
}

public struct UpdateSessionAccessRequest: Encodable, Sendable {
    public var editors: [Int64]
    public var viewers: [Int64]

    public init(editors: [Int64], viewers: [Int64]) {
        self.editors = editors
        self.viewers = viewers
    }
}

public struct CreateSessionRequest: Encodable, Sendable {
    public var name: String
    public var enabled: Bool
    public var protocols: [Int64]

    public init(name: String, enabled: Bool = true, protocols: [Int64] = []) {
        self.name = name
        self.enabled = enabled
        self.protocols = protocols
    }
}

public struct UpdateSessionRequest: Encodable, Sendable {
    public var name: String
    public var enabled: Bool

    public init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
    }
}
