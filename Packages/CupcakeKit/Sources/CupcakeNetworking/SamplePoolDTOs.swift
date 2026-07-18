public struct SamplePoolDTO: Decodable, Sendable {
    public let id: Int64
    public let poolName: String
    public let poolDescription: String?
    public let pooledOnlySamples: [Int]
    public let pooledAndIndependentSamples: [Int]
    public let isReference: Bool
    public let sdrfValue: String?
    public let metadataTable: Int64
    public let totalSamples: Int?
    public let metadataColumns: [MetadataColumnDTO]?

    public init(
        id: Int64,
        poolName: String,
        poolDescription: String?,
        pooledOnlySamples: [Int],
        pooledAndIndependentSamples: [Int],
        isReference: Bool,
        sdrfValue: String?,
        metadataTable: Int64,
        totalSamples: Int?,
        metadataColumns: [MetadataColumnDTO]? = nil
    ) {
        self.id = id
        self.poolName = poolName
        self.poolDescription = poolDescription
        self.pooledOnlySamples = pooledOnlySamples
        self.pooledAndIndependentSamples = pooledAndIndependentSamples
        self.isReference = isReference
        self.sdrfValue = sdrfValue
        self.metadataTable = metadataTable
        self.totalSamples = totalSamples
        self.metadataColumns = metadataColumns
    }
}

public struct CreateSamplePoolRequest: Encodable, Sendable {
    public var metadataTable: Int64
    public var poolName: String
    public var poolDescription: String?
    public var pooledOnlySamples: [Int]
    public var pooledAndIndependentSamples: [Int]
    public var isReference: Bool

    public init(
        metadataTable: Int64,
        poolName: String,
        poolDescription: String?,
        pooledOnlySamples: [Int],
        pooledAndIndependentSamples: [Int],
        isReference: Bool
    ) {
        self.metadataTable = metadataTable
        self.poolName = poolName
        self.poolDescription = poolDescription
        self.pooledOnlySamples = pooledOnlySamples
        self.pooledAndIndependentSamples = pooledAndIndependentSamples
        self.isReference = isReference
    }
}

public struct UpdateSamplePoolRequest: Encodable, Sendable {
    public var poolName: String
    public var poolDescription: String?
    public var pooledOnlySamples: [Int]
    public var pooledAndIndependentSamples: [Int]
    public var isReference: Bool

    public init(
        poolName: String,
        poolDescription: String?,
        pooledOnlySamples: [Int],
        pooledAndIndependentSamples: [Int],
        isReference: Bool
    ) {
        self.poolName = poolName
        self.poolDescription = poolDescription
        self.pooledOnlySamples = pooledOnlySamples
        self.pooledAndIndependentSamples = pooledAndIndependentSamples
        self.isReference = isReference
    }
}
