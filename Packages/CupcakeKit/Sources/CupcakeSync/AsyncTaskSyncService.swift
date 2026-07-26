import CupcakeNetworking
import Foundation

public actor AsyncTaskSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?

    public init(apiClient: APIClient, deviceToken: @escaping @Sendable () -> String?) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
    }

    public func fetchAll(
        taskType: String? = nil, status: String? = nil, metadataTableServerID: Int64? = nil,
        limit: Int = 50, offset: Int = 0
    ) async throws -> (count: Int, results: [AsyncTaskDTO]) {
        guard let token = deviceToken() else { return (0, []) }
        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let taskType { query.append(URLQueryItem(name: "task_type", value: taskType)) }
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        if let metadataTableServerID {
            query.append(URLQueryItem(name: "metadata_table", value: String(metadataTableServerID)))
        }
        let response: PaginatedResponse<AsyncTaskDTO> = try await apiClient.get(
            "async-tasks/", query: query, authorizationHeader: "DeviceToken \(token)"
        )
        return (response.count, response.results)
    }

    public func fetchDetail(id: String) async throws -> AsyncTaskDTO {
        guard let token = deviceToken() else { throw AsyncTaskSyncError.noDeviceToken }
        return try await apiClient.get("async-tasks/\(id)/", authorizationHeader: "DeviceToken \(token)")
    }

    public func cancel(id: String) async throws {
        guard let token = deviceToken() else { throw AsyncTaskSyncError.noDeviceToken }
        try await apiClient.sendNoContent("async-tasks/\(id)/cancel/", method: .delete, authorizationHeader: "DeviceToken \(token)")
    }

    public func cleanupCompleted() async throws {
        guard let token = deviceToken() else { throw AsyncTaskSyncError.noDeviceToken }
        try await apiClient.sendNoContent("async-tasks/cleanup_completed/", method: .delete, authorizationHeader: "DeviceToken \(token)")
    }

    public func fetchDownloadURL(id: String) async throws -> AsyncTaskDownloadURLResponse {
        guard let token = deviceToken() else { throw AsyncTaskSyncError.noDeviceToken }
        return try await apiClient.get("async-tasks/\(id)/download_url/", authorizationHeader: "DeviceToken \(token)")
    }

    public func downloadFile(id: String) async throws -> (data: Data, suggestedFilename: String?) {
        let info = try await fetchDownloadURL(id: id)
        guard let url = URL(string: info.downloadURL) else { throw AsyncTaskSyncError.invalidDownloadURL }
        return try await apiClient.downloadData(from: url, authorizationHeader: nil)
    }

    @discardableResult
    public func exportSDRFFile(metadataTableServerID: Int64, metadataColumnIDs: [Int64], sampleNumber: Int, includePools: Bool) async throws -> String {
        try await submitExport(action: "sdrf_file", metadataTableServerID: metadataTableServerID, metadataColumnIDs: metadataColumnIDs, sampleNumber: sampleNumber, includePools: includePools)
    }

    @discardableResult
    public func exportExcelTemplate(metadataTableServerID: Int64, metadataColumnIDs: [Int64], sampleNumber: Int, includePools: Bool) async throws -> String {
        try await submitExport(action: "excel_template", metadataTableServerID: metadataTableServerID, metadataColumnIDs: metadataColumnIDs, sampleNumber: sampleNumber, includePools: includePools)
    }

    private func submitExport(action: String, metadataTableServerID: Int64, metadataColumnIDs: [Int64], sampleNumber: Int, includePools: Bool) async throws -> String {
        guard let token = deviceToken() else { throw AsyncTaskSyncError.noDeviceToken }
        let request = AsyncExportRequest(
            metadataTableID: metadataTableServerID, metadataColumnIds: metadataColumnIDs,
            sampleNumber: sampleNumber, includePools: includePools
        )
        let response: AsyncTaskCreatedResponse = try await apiClient.send(
            "async-export/\(action)/", method: .post, body: request, authorizationHeader: "DeviceToken \(token)"
        )
        return response.taskID
    }

    @discardableResult
    public func importSDRFFile(
        metadataTableServerID: Int64, fileURL: URL, replaceExisting: Bool,
        importScope: AsyncMetadataImportScope = .userMetadata, validateOntologies: Bool = true, applySchemaTemplates: Bool = false
    ) async throws -> String {
        try await submitImport(
            action: "sdrf_file", metadataTableServerID: metadataTableServerID, fileURL: fileURL,
            mimeType: "text/tab-separated-values", replaceExisting: replaceExisting, importScope: importScope,
            validateOntologies: validateOntologies, applySchemaTemplates: applySchemaTemplates
        )
    }

    @discardableResult
    public func importExcelFile(
        metadataTableServerID: Int64, fileURL: URL, replaceExisting: Bool,
        importScope: AsyncMetadataImportScope = .userMetadata, validateOntologies: Bool = true
    ) async throws -> String {
        try await submitImport(
            action: "excel_file", metadataTableServerID: metadataTableServerID, fileURL: fileURL,
            mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            replaceExisting: replaceExisting, importScope: importScope, validateOntologies: validateOntologies, applySchemaTemplates: false
        )
    }

    private func submitImport(
        action: String, metadataTableServerID: Int64, fileURL: URL, mimeType: String,
        replaceExisting: Bool, importScope: AsyncMetadataImportScope, validateOntologies: Bool, applySchemaTemplates: Bool
    ) async throws -> String {
        guard let token = deviceToken() else { throw AsyncTaskSyncError.noDeviceToken }
        let fileData = try Data(contentsOf: fileURL)
        var form = MultipartFormBuilder()
        form.addField(name: "metadata_table_id", value: String(metadataTableServerID))
        form.addField(name: "replace_existing", value: replaceExisting ? "true" : "false")
        form.addField(name: "import_type", value: importScope.rawValue)
        form.addField(name: "validate_ontologies", value: validateOntologies ? "true" : "false")
        if action == "sdrf_file" {
            form.addField(name: "apply_schema_templates", value: applySchemaTemplates ? "true" : "false")
        }
        form.addFile(name: "file", filename: fileURL.lastPathComponent, mimeType: mimeType, data: fileData)
        let response: AsyncTaskCreatedResponse = try await apiClient.sendMultipart(
            "async-import/\(action)/", body: form, authorizationHeader: "DeviceToken \(token)"
        )
        return response.taskID
    }
}

public enum AsyncTaskSyncError: Error {
    case noDeviceToken
    case invalidDownloadURL
}
