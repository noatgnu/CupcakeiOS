/// Verified against `ccv/models.py:1291-1374` (`MetadataColumn`) and `MetadataColumnSerializer`
/// (`ccv/serializers.py:170-207`). Read-only in this app's v1 slice — no create/edit path
/// (`update_column_value` is deferred to a later slice).
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
