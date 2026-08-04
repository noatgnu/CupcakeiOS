import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor ProjectSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: ProjectStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = ProjectStore(modelContainer: modelContainer)
    }

    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        try await apiClient.fetchAllPages(path: "projects/", authorizationHeader: "DeviceToken \(token)") { (dtos: [ProjectDTO]) in
            try await store.upsert(dtos)
        }
    }

    @discardableResult
    public func syncLocallyCreatedProject(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw ProjectSyncError.noDeviceToken
        }
        let fields = try await store.projectFields(clientID: clientID)
        let dto: ProjectDTO = try await apiClient.send(
            "projects/",
            method: .post,
            body: CreateProjectRequest(projectName: fields.projectName, projectDescription: fields.projectDescription),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(clientID: clientID, dto: dto)
        return dto.id
    }

    @discardableResult
    public func update(serverID: Int64, projectName: String, projectDescription: String?) async throws -> ProjectDTO {
        guard let token = deviceToken() else {
            throw ProjectSyncError.noDeviceToken
        }
        let dto: ProjectDTO = try await apiClient.send(
            "projects/\(serverID)/",
            method: .patch,
            body: UpdateProjectRequest(projectName: projectName, projectDescription: projectDescription),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    public func delete(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw ProjectSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "projects/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeLocal(serverID: serverID)
    }
}

public enum ProjectSyncError: Error {
    case noDeviceToken
    case projectNotCached
}

@ModelActor
actor ProjectStore {
    func upsert(_ dtos: [ProjectDTO]) throws {
        for dto in dtos {
            let projectServerID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedProject>(predicate: #Predicate { $0.serverID == projectServerID })
            )
            let project = existing?.first ?? {
                let created = CachedProject(
                    serverID: dto.id,
                    projectName: dto.projectName,
                    projectDescription: dto.projectDescription,
                    createdAt: Date.parsedISO8601(dto.createdAt)
                )
                modelContext.insert(created)
                return created
            }()
            project.projectName = dto.projectName
            project.projectDescription = dto.projectDescription
            project.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: project.updatedAt)
        }
        try modelContext.save()
    }

    func projectFields(clientID: UUID) throws -> (projectName: String, projectDescription: String?) {
        guard let project = try modelContext.fetch(
            FetchDescriptor<CachedProject>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProjectSyncError.projectNotCached
        }
        return (project.projectName, project.projectDescription)
    }

    func attachServerID(clientID: UUID, dto: ProjectDTO) throws {
        guard let project = try modelContext.fetch(
            FetchDescriptor<CachedProject>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProjectSyncError.projectNotCached
        }
        project.serverID = dto.id
        project.projectName = dto.projectName
        project.projectDescription = dto.projectDescription
        project.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: project.updatedAt)
        try modelContext.save()
    }

    func removeLocal(serverID: Int64) throws {
        guard let project = try modelContext.fetch(
            FetchDescriptor<CachedProject>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        modelContext.delete(project)
        try modelContext.save()
    }
}
