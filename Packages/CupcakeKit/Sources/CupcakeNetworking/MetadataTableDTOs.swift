public struct MetadataColumnModifierDTO: Codable, Sendable {
    public let samples: String
    public let value: String
}

public struct MetadataColumnDTO: Decodable, Sendable, Identifiable {
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

    public init(
        id: Int64,
        name: String,
        displayName: String?,
        type: String,
        columnPosition: Int?,
        value: String?,
        notApplicable: Bool,
        notAvailable: Bool,
        mandatory: Bool,
        hidden: Bool,
        readonly: Bool,
        ontologyType: String?,
        staffOnly: Bool,
        modifiers: [MetadataColumnModifierDTO]
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.type = type
        self.columnPosition = columnPosition
        self.value = value
        self.notApplicable = notApplicable
        self.notAvailable = notAvailable
        self.mandatory = mandatory
        self.hidden = hidden
        self.readonly = readonly
        self.ontologyType = ontologyType
        self.staffOnly = staffOnly
        self.modifiers = modifiers
    }

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

public struct UpdateMetadataColumnRequest: Encodable, Sendable {
    public var name: String?
    public var type: String?
    public var columnPosition: Int?
    public var mandatory: Bool?
    public var hidden: Bool?
    public var readonly: Bool?
    public var staffOnly: Bool?
    public var ontologyType: String?

    public init(
        name: String? = nil,
        type: String? = nil,
        columnPosition: Int? = nil,
        mandatory: Bool? = nil,
        hidden: Bool? = nil,
        readonly: Bool? = nil,
        staffOnly: Bool? = nil,
        ontologyType: String? = nil
    ) {
        self.name = name
        self.type = type
        self.columnPosition = columnPosition
        self.mandatory = mandatory
        self.hidden = hidden
        self.readonly = readonly
        self.staffOnly = staffOnly
        self.ontologyType = ontologyType
    }
}

public struct MetadataTableDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let sampleCount: Int
    public let version: String
    public let owner: Int64?
    public let ownerUsername: String?
    public let labGroup: Int64?
    public let labGroupName: String?
    public let isPublished: Bool
    public let isLocked: Bool
    public let columnCount: Int
    public let sampleRange: String?
    public let canEdit: Bool
    public let columns: [MetadataColumnDTO]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        version = try container.decode(String.self, forKey: .version)
        owner = try container.decodeIfPresent(Int64.self, forKey: .owner)
        ownerUsername = try container.decodeIfPresent(String.self, forKey: .ownerUsername)
        labGroup = try container.decodeIfPresent(Int64.self, forKey: .labGroup)
        labGroupName = try container.decodeIfPresent(String.self, forKey: .labGroupName)
        isPublished = try container.decode(Bool.self, forKey: .isPublished)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        columnCount = try container.decodeIfPresent(Int.self, forKey: .columnCount) ?? 0
        sampleRange = try container.decodeIfPresent(String.self, forKey: .sampleRange)
        canEdit = try container.decode(Bool.self, forKey: .canEdit)
        columns = try container.decode([MetadataColumnDTO].self, forKey: .columns)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, sampleCount, version, owner, ownerUsername
        case labGroup, labGroupName, isPublished, isLocked, columnCount, sampleRange, canEdit, columns
    }
}

public struct CreateMetadataFromTemplateResponse: Decodable, Sendable {
    public let message: String
    public let metadataTable: MetadataTableDTO
    public let jobId: Int64
}

public struct UpdateMetadataTableRequest: Encodable, Sendable {
    public var name: String?
    public var description: String?
    public var sampleCount: Int?
    public var sampleCountConfirmed: Bool?
    public var labGroup: Int64?
    public var isPublished: Bool?
    public var isLocked: Bool?

    public init(
        name: String? = nil,
        description: String? = nil,
        sampleCount: Int? = nil,
        sampleCountConfirmed: Bool? = nil,
        labGroup: Int64? = nil,
        isPublished: Bool? = nil,
        isLocked: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.sampleCount = sampleCount
        self.sampleCountConfirmed = sampleCountConfirmed
        self.labGroup = labGroup
        self.isPublished = isPublished
        self.isLocked = isLocked
    }
}

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

public struct UpdateColumnValueResponse: Decodable, Sendable {
    public let column: MetadataColumnDTO
}

public struct UnimodFullData: Decodable, Sendable {
    public let accession: String?
    public let name: String?
    public let definition: String?
    public let deltaMonoMass: String?
    public let deltaComposition: String?
    public let specifications: [String: [String: String]]

    private enum CodingKeys: String, CodingKey {
        case accession, name, definition, deltaMonoMass, deltaComposition, specifications
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accession = try container.decodeIfPresent(String.self, forKey: .accession)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        definition = try container.decodeIfPresent(String.self, forKey: .definition)
        deltaMonoMass = try container.decodeIfPresent(String.self, forKey: .deltaMonoMass)
        deltaComposition = try container.decodeIfPresent(String.self, forKey: .deltaComposition)
        specifications = try container.decodeIfPresent([String: [String: String]].self, forKey: .specifications) ?? [:]
    }
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
    public let defaultPosition: Int?
    public let category: String?
    public let schemaName: String?
    public let isSystemTemplate: Bool
    public let visibility: String
    public let labGroup: Int64?
    public let labGroupName: String?
    public let canEdit: Bool
    public let canDelete: Bool
    public let enableTypeahead: Bool
    public let notAvailable: Bool
    public let excelValidation: Bool
    public let tags: [String]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        columnName = try container.decode(String.self, forKey: .columnName)
        columnType = try container.decode(String.self, forKey: .columnType)
        ontologyType = try container.decodeIfPresent(String.self, forKey: .ontologyType)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        defaultPosition = try container.decodeIfPresent(Int.self, forKey: .defaultPosition)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        schemaName = try container.decodeIfPresent(String.self, forKey: .schemaName)
        isSystemTemplate = try container.decode(Bool.self, forKey: .isSystemTemplate)
        visibility = try container.decode(String.self, forKey: .visibility)
        labGroup = try container.decodeIfPresent(Int64.self, forKey: .labGroup)
        labGroupName = try container.decodeIfPresent(String.self, forKey: .labGroupName)
        canEdit = try container.decode(Bool.self, forKey: .canEdit)
        canDelete = try container.decode(Bool.self, forKey: .canDelete)
        enableTypeahead = try container.decodeIfPresent(Bool.self, forKey: .enableTypeahead) ?? true
        notAvailable = try container.decodeIfPresent(Bool.self, forKey: .notAvailable) ?? false
        excelValidation = try container.decodeIfPresent(Bool.self, forKey: .excelValidation) ?? true
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, columnName, columnType, ontologyType, defaultValue, defaultPosition
        case category, schemaName, isSystemTemplate, visibility, labGroup, labGroupName, canEdit, canDelete
        case enableTypeahead, notAvailable, excelValidation, tags
    }
}

public struct GroupedColumnTemplateDTO: Decodable, Sendable, Identifiable {
    public let columnName: String
    public let columnType: String
    public let schemaCount: Int
    public let schemas: [String]
    public let templateIds: [Int64]
    public let sampleTemplate: MetadataColumnTemplateDTO?

    public var id: String { columnName }
}

public struct CreateColumnTemplateRequest: Encodable, Sendable {
    public var name: String
    public var description: String?
    public var columnName: String
    public var columnType: String
    public var ontologyType: String?
    public var defaultValue: String?
    public var defaultPosition: Int?
    public var visibility: String
    public var labGroup: Int64?
    public var category: String?
    public var enableTypeahead: Bool
    public var notAvailable: Bool
    public var excelValidation: Bool
    public var tags: [String]

    public init(
        name: String,
        description: String? = nil,
        columnName: String,
        columnType: String,
        ontologyType: String? = nil,
        defaultValue: String? = nil,
        defaultPosition: Int? = nil,
        visibility: String = "private",
        labGroup: Int64? = nil,
        category: String? = nil,
        enableTypeahead: Bool = true,
        notAvailable: Bool = false,
        excelValidation: Bool = true,
        tags: [String] = []
    ) {
        self.name = name
        self.description = description
        self.columnName = columnName
        self.columnType = columnType
        self.ontologyType = ontologyType
        self.defaultValue = defaultValue
        self.defaultPosition = defaultPosition
        self.visibility = visibility
        self.labGroup = labGroup
        self.category = category
        self.enableTypeahead = enableTypeahead
        self.notAvailable = notAvailable
        self.excelValidation = excelValidation
        self.tags = tags
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

public struct BulkUpdateSampleValueEntry: Encodable, Sendable {
    public var sampleIndex: Int
    public var value: String

    public init(sampleIndex: Int, value: String) {
        self.sampleIndex = sampleIndex
        self.value = value
    }
}

public struct BulkUpdateSampleValuesRequest: Encodable, Sendable {
    public var updates: [BulkUpdateSampleValueEntry]

    public init(updates: [BulkUpdateSampleValueEntry]) {
        self.updates = updates
    }
}

public struct BulkUpdateSampleValuesResponse: Decodable, Sendable {
    public let message: String
    public let updatedCount: Int
    public let failedCount: Int
    public let column: MetadataColumnDTO
}

public struct AutofillVariationSpec: Encodable, Sendable {
    public var columnId: Int64
    public var type: String
    public var start: Int?
    public var end: Int?
    public var step: Int?
    public var values: [String]?
    public var pattern: String?
    public var count: Int?

    public static func range(columnId: Int64, start: Int, end: Int, step: Int = 1) -> AutofillVariationSpec {
        AutofillVariationSpec(columnId: columnId, type: "range", start: start, end: end, step: step, values: nil, pattern: nil, count: nil)
    }

    public static func list(columnId: Int64, values: [String]) -> AutofillVariationSpec {
        AutofillVariationSpec(columnId: columnId, type: "list", start: nil, end: nil, step: nil, values: values, pattern: nil, count: nil)
    }

    public static func pattern(columnId: Int64, pattern: String, count: Int) -> AutofillVariationSpec {
        AutofillVariationSpec(columnId: columnId, type: "pattern", start: nil, end: nil, step: nil, values: nil, pattern: pattern, count: count)
    }
}

public enum AutofillFillStrategy: String, Sendable, CaseIterable {
    case cartesianProduct = "cartesian_product"
    case sequential
    case interleaved

    public var displayName: String {
        switch self {
        case .cartesianProduct: return "Cartesian Product"
        case .sequential: return "Sequential"
        case .interleaved: return "Interleaved"
        }
    }
}

public struct AdvancedAutofillRequest: Sendable {
    public var templateSamples: [Int]
    public var targetSampleCount: Int
    public var variations: [AutofillVariationSpec]
    public var fillStrategy: AutofillFillStrategy

    public init(templateSamples: [Int], targetSampleCount: Int, variations: [AutofillVariationSpec], fillStrategy: AutofillFillStrategy) {
        self.templateSamples = templateSamples
        self.targetSampleCount = targetSampleCount
        self.variations = variations
        self.fillStrategy = fillStrategy
    }

    public var rawJSON: [String: Any] {
        [
            "templateSamples": templateSamples,
            "targetSampleCount": targetSampleCount,
            "fillStrategy": fillStrategy.rawValue,
            "variations": variations.map { variation -> [String: Any] in
                var dict: [String: Any] = ["columnId": variation.columnId, "type": variation.type]
                if let start = variation.start { dict["start"] = start }
                if let end = variation.end { dict["end"] = end }
                if let step = variation.step { dict["step"] = step }
                if let values = variation.values { dict["values"] = values }
                if let pattern = variation.pattern { dict["pattern"] = pattern }
                if let count = variation.count { dict["count"] = count }
                return dict
            },
        ]
    }
}

public struct AdvancedAutofillResponse: Decodable, Sendable {
    public let status: String?
    public let samplesModified: Int?
    public let columnsModified: Int?
    public let variationsCombinations: Int?
    public let strategy: String?
}
