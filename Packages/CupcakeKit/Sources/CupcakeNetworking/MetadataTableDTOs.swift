/// Verified against `ccv/models.py:1291-1374` (`MetadataColumn`) and `MetadataColumnSerializer`
/// (`ccv/serializers.py:170-207`).
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
}

/// Verified against `ccv/models.py:23-244` (`BaseMetadataTable`/`MetadataTable`) and
/// `MetadataTableSerializer` (`ccv/serializers.py:36-98`). `columns` is a nested read-only field
/// on every `MetadataTable` response — no separate `metadata-columns/` call is needed to read a
/// table's columns.
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

/// `POST instrument-jobs/{id}/create_metadata_from_template/` response — does **not** return the
/// updated `InstrumentJob` itself, only the new table and the job's id (`ccm/viewsets.py:588-669`).
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

/// `POST metadata-columns/{id}/update_column_value/` body. Field set/behavior verified directly
/// against `ccv/viewsets.py:1400-1460` (not assumed from the Angular frontend alone): `.default`
/// sets the column's own default value; `.sampleSpecific` requires `sampleIndices` (1-based sample
/// numbers) and stores per-sample overrides via modifiers; `.replaceAll` isn't yet exposed by this
/// app's v1 slice (deferred alongside bulk/pattern autofill).
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

/// Only `column` is actually consumed — `message`/`changes`/`value_type` exist on the real
/// response but this app's v1 slice has no use for them yet (no undo/diff UI).
public struct UpdateColumnValueResponse: Decodable, Sendable {
    public let column: MetadataColumnDTO
}

/// `GET metadata-columns/ontology_suggestions/?column_id=&search=&limit=&search_type=` (or the
/// `column-templates/` equivalent). Verified against `ccv/ontology_registry.py`'s
/// `OntologyDescriptor.build_search_queryset` response envelope, not assumed. `fullData` varies by
/// ontology type (e.g. Unimod's `deltaMonoMass`/`deltaComposition`/specifications) — left as a
/// generic JSON blob (`[String: JSONValue]`) rather than typed per-ontology, since this app's v1
/// slice only needs `value`/`displayName` for plain-text columns, not the SDRF special-syntax
/// auto-fill behavior the reference web app's modification/cleavage inputs use.
public struct OntologySuggestionDTO: Decodable, Sendable, Identifiable {
    public let id: String
    public let value: String
    public let displayName: String
    public let description: String?
    public let ontologyType: String
}

public struct OntologySuggestionsResponse: Decodable, Sendable {
    public let suggestions: [OntologySuggestionDTO]
}
