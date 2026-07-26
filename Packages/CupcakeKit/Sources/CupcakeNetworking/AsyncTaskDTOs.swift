import Foundation

public struct AsyncTaskDTO: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let taskType: String
    public let status: String
    public let metadataTableID: Int64?
    public let metadataTableName: String?
    public let progressPercentage: Double
    public let progressDescription: String
    public let createdAt: String?
    public let startedAt: String?
    public let completedAt: String?
    public let duration: Double?
    public let errorMessage: String
    public let traceback: String?

    private enum CodingKeys: String, CodingKey {
        case id, taskType, status, metadataTable, metadataTableId, metadataTableName
        case progressPercentage, progressDescription, createdAt, startedAt, completedAt
        case duration, errorMessage, traceback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        taskType = try container.decode(String.self, forKey: .taskType)
        status = try container.decode(String.self, forKey: .status)
        metadataTableID = try container.decodeIfPresent(Int64.self, forKey: .metadataTableId)
            ?? container.decodeIfPresent(Int64.self, forKey: .metadataTable)
        metadataTableName = try container.decodeIfPresent(String.self, forKey: .metadataTableName)
        progressPercentage = try container.decodeIfPresent(Double.self, forKey: .progressPercentage) ?? 0
        progressDescription = try container.decodeIfPresent(String.self, forKey: .progressDescription) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        traceback = try container.decodeIfPresent(String.self, forKey: .traceback)
    }

    public init(
        id: String, taskType: String, status: String, metadataTableID: Int64?, metadataTableName: String?,
        progressPercentage: Double, progressDescription: String, createdAt: String?, startedAt: String?,
        completedAt: String?, duration: Double?, errorMessage: String, traceback: String?
    ) {
        self.id = id
        self.taskType = taskType
        self.status = status
        self.metadataTableID = metadataTableID
        self.metadataTableName = metadataTableName
        self.progressPercentage = progressPercentage
        self.progressDescription = progressDescription
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.duration = duration
        self.errorMessage = errorMessage
        self.traceback = traceback
    }

    public var isTerminal: Bool {
        status == "SUCCESS" || status == "FAILURE" || status == "CANCELLED"
    }
}

public enum AsyncMetadataImportScope: String, Sendable, CaseIterable {
    case userMetadata = "user_metadata"
    case staffMetadata = "staff_metadata"
    case both = "both"

    public var displayName: String {
        switch self {
        case .userMetadata: return "User Columns Only"
        case .staffMetadata: return "Staff Columns Only"
        case .both: return "All Columns"
        }
    }
}

public struct AsyncExportRequest: Encodable, Sendable {
    public let metadataTableID: Int64
    public let metadataColumnIds: [Int64]
    public let sampleNumber: Int
    public let includePools: Bool

    public init(metadataTableID: Int64, metadataColumnIds: [Int64], sampleNumber: Int, includePools: Bool) {
        self.metadataTableID = metadataTableID
        self.metadataColumnIds = metadataColumnIds
        self.sampleNumber = sampleNumber
        self.includePools = includePools
    }
}

public struct AsyncTaskCreatedResponse: Decodable, Sendable {
    public let taskID: String
    public let message: String

    private enum CodingKeys: String, CodingKey {
        case taskID = "taskId"
        case message
    }
}

public struct AsyncTaskDownloadURLResponse: Decodable, Sendable {
    public let downloadURL: String
    public let filename: String
    public let contentType: String?
    public let fileSize: Int?

    private enum CodingKeys: String, CodingKey {
        case downloadURL = "downloadUrl"
        case filename, contentType, fileSize
    }
}
