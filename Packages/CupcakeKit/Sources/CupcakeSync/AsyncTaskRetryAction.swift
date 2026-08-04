import CupcakeNetworking
import Foundation

public enum AsyncTaskRetryAction: Sendable {
    case exportSDRF(metadataTableServerID: Int64, metadataColumnIDs: [Int64], sampleNumber: Int, includePools: Bool)
    case exportExcel(metadataTableServerID: Int64, metadataColumnIDs: [Int64], sampleNumber: Int, includePools: Bool)
    case importSDRF(metadataTableServerID: Int64, fileData: Data, fileName: String, replaceExisting: Bool, importScope: AsyncMetadataImportScope)
    case importExcel(metadataTableServerID: Int64, fileData: Data, fileName: String, replaceExisting: Bool, importScope: AsyncMetadataImportScope)

    public func resubmit(using asyncTaskSync: AsyncTaskSyncService) async throws -> String {
        switch self {
        case .exportSDRF(let metadataTableServerID, let metadataColumnIDs, let sampleNumber, let includePools):
            return try await asyncTaskSync.exportSDRFFile(
                metadataTableServerID: metadataTableServerID, metadataColumnIDs: metadataColumnIDs,
                sampleNumber: sampleNumber, includePools: includePools
            )
        case .exportExcel(let metadataTableServerID, let metadataColumnIDs, let sampleNumber, let includePools):
            return try await asyncTaskSync.exportExcelTemplate(
                metadataTableServerID: metadataTableServerID, metadataColumnIDs: metadataColumnIDs,
                sampleNumber: sampleNumber, includePools: includePools
            )
        case .importSDRF(let metadataTableServerID, let fileData, let fileName, let replaceExisting, let importScope):
            return try await asyncTaskSync.importSDRFFile(
                metadataTableServerID: metadataTableServerID, fileData: fileData, fileName: fileName,
                replaceExisting: replaceExisting, importScope: importScope
            )
        case .importExcel(let metadataTableServerID, let fileData, let fileName, let replaceExisting, let importScope):
            return try await asyncTaskSync.importExcelFile(
                metadataTableServerID: metadataTableServerID, fileData: fileData, fileName: fileName,
                replaceExisting: replaceExisting, importScope: importScope
            )
        }
    }
}
