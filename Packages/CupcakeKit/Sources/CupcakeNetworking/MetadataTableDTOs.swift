/// A per-sample-range value override, e.g. `{"samples": "1-3,7", "value": "..."}`.
public struct MetadataColumnModifierDTO: Codable, Sendable {
    public let samples: String
    public let value: String
}

/// `GET metadata-columns/` response shape.
public struct MetadataColumnDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let displayName: String?
    public let type: String
    public let columnPosition: Int?
    public let value: String?
    public let notApplicable: Bool
    public let notAvailable: Bool
    public let mandatory: Bool
    public let hidden: Bool
    public let readonly: Bool
    public let ontologyType: String?
    public let staffOnly: Bool
    public let modifiers: [MetadataColumnModifierDTO]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        type = try container.decode(String.self, forKey: .type)
        columnPosition = try container.decodeIfPresent(Int.self, forKey: .columnPosition)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        notApplicable = try container.decode(Bool.self, forKey: .notApplicable)
        notAvailable = try container.decode(Bool.self, forKey: .notAvailable)
        mandatory = try container.decode(Bool.self, forKey: .mandatory)
        hidden = try container.decode(Bool.self, forKey: .hidden)
        readonly = try container.decode(Bool.self, forKey: .readonly)
        ontologyType = try container.decodeIfPresent(String.self, forKey: .ontologyType)
        staffOnly = try container.decode(Bool.self, forKey: .staffOnly)
        modifiers = try container.decodeIfPresent([MetadataColumnModifierDTO].self, forKey: .modifiers) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, type, columnPosition, value, notApplicable, notAvailable
        case mandatory, hidden, readonly, ontologyType, staffOnly, modifiers
    }
}

/// `GET metadata-tables/` response shape. `columns` is a nested read-only field, no separate call needed.
public struct MetadataTableDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let sampleCount: Int
    public let version: String
    public let ownerUsername: String?
    public let labGroupName: String?
    public let isPublished: Bool
    public let canEdit: Bool
    public let columns: [MetadataColumnDTO]
}

/// `POST instrument-jobs/{id}/create_metadata_from_template/` response — does not return the updated `InstrumentJob` itself.
public struct CreateMetadataFromTemplateResponse: Decodable, Sendable {
    public let message: String
    public let metadataTable: MetadataTableDTO
    public let jobId: Int64
}

/// `POST instrument-jobs/{id}/create_metadata_from_template/` request body.
public struct CreateMetadataFromTemplateRequest: Encodable, Sendable {
    public var templateId: Int64
    public var sampleCount: Int?
    public var labGroupId: Int64?

    public init(templateId: Int64, sampleCount: Int? = nil, labGroupId: Int64? = nil) {
        self.templateId = templateId
        self.sampleCount = sampleCount
        self.labGroupId = labGroupId
    }
}

/// `POST metadata-columns/{id}/update_column_value/` body's value type. `.replaceAll` isn't yet exposed by this app.
public enum ColumnValueUpdateType: String, Encodable, Sendable {
    case `default`
    case sampleSpecific = "sample_specific"
    case replaceAll = "replace_all"
}

public struct UpdateColumnValueRequest: Encodable, Sendable {
    public var value: String
    public var sampleIndices: [Int]?
    public var valueType: ColumnValueUpdateType

    public init(value: String, sampleIndices: [Int]? = nil, valueType: ColumnValueUpdateType = .default) {
        self.value = value
        self.sampleIndices = sampleIndices
        self.valueType = valueType
    }
}

/// Only `column` is consumed; the response also carries `message`/`changes`/`value_type`, unused here.
public struct UpdateColumnValueResponse: Decodable, Sendable {
    public let column: MetadataColumnDTO
}

/// A Unimod ontology suggestion's extra detail fields.
public struct UnimodFullData: Decodable, Sendable {
    public let accession: String?
    public let name: String?
    public let definition: String?
    public let deltaMonoMass: String?
    public let deltaComposition: String?
    public let specifications: [String: [String: String]]
}

public struct OntologySuggestionDTO: Decodable, Sendable, Identifiable {
    public let id: String
    public let value: String
    public let displayName: String
    public let description: String?
    public let ontologyType: String
    public let fullData: UnimodFullData?
}

public struct OntologySuggestionsResponse: Decodable, Sendable {
    public let suggestions: [OntologySuggestionDTO]
}

public struct MetadataColumnTemplateDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let columnName: String
    public let columnType: String
    public let ontologyType: String?
    public let defaultValue: String?
    public let category: String?
    public let isSystemTemplate: Bool
    public let visibility: String
    public let labGroup: Int64?
    public let canEdit: Bool
    public let canDelete: Bool
}

public struct CreateColumnTemplateRequest: Encodable, Sendable {
    public var name: String
    public var description: String?
    public var columnName: String
    public var columnType: String
    public var ontologyType: String?
    public var defaultValue: String?
    public var visibility: String
    public var labGroup: Int64?
    public var category: String?

    public init(
        name: String,
        description: String? = nil,
        columnName: String,
        columnType: String,
        ontologyType: String? = nil,
        defaultValue: String? = nil,
        visibility: String = "private",
        labGroup: Int64? = nil,
        category: String? = nil
    ) {
        self.name = name
        self.description = description
        self.columnName = columnName
        self.columnType = columnType
        self.ontologyType = ontologyType
        self.defaultValue = defaultValue
        self.visibility = visibility
        self.labGroup = labGroup
        self.category = category
    }
}

public struct AddColumnDataRequest: Encodable, Sendable {
    public var name: String
    public var type: String
    public var ontologyType: String?
    public var value: String?

    public init(name: String, type: String, ontologyType: String? = nil, value: String? = nil) {
        self.name = name
        self.type = type
        self.ontologyType = ontologyType
        self.value = value
    }
}

public struct AddColumnWithAutoReorderRequest: Encodable, Sendable {
    public var columnData: AddColumnDataRequest

    public init(columnData: AddColumnDataRequest) {
        self.columnData = columnData
    }
}

public struct AddColumnWithAutoReorderResponse: Decodable, Sendable {
    public let message: String
    public let column: MetadataColumnDTO
}

public struct RemoveColumnRequest: Encodable, Sendable {
    public var columnId: Int64

    public init(columnId: Int64) {
        self.columnId = columnId
    }
}

public struct RemoveColumnResponse: Decodable, Sendable {
    public let message: String
}
