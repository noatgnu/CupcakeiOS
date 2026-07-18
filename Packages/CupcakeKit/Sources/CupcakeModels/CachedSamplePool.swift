import Foundation
import SwiftData

@Model
public final class CachedSamplePool {
    @Attribute(.unique) public var serverID: Int64
    public var metadataTableServerID: Int64
    public var poolName: String
    public var poolDescription: String?
    public var pooledOnlySamples: [Int]
    public var pooledAndIndependentSamples: [Int]
    public var isReference: Bool
    public var sdrfValue: String?
    public var totalSamples: Int

    public init(
        serverID: Int64,
        metadataTableServerID: Int64,
        poolName: String,
        poolDescription: String? = nil,
        pooledOnlySamples: [Int] = [],
        pooledAndIndependentSamples: [Int] = [],
        isReference: Bool = false,
        sdrfValue: String? = nil,
        totalSamples: Int = 0
    ) {
        self.serverID = serverID
        self.metadataTableServerID = metadataTableServerID
        self.poolName = poolName
        self.poolDescription = poolDescription
        self.pooledOnlySamples = pooledOnlySamples
        self.pooledAndIndependentSamples = pooledAndIndependentSamples
        self.isReference = isReference
        self.sdrfValue = sdrfValue
        self.totalSamples = totalSamples
    }
}
