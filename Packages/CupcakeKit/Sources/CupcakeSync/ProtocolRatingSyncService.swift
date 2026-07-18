import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor ProtocolRatingSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: ProtocolRatingStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = ProtocolRatingStore(modelContainer: modelContainer)
    }

    public func refetchMyRating(protocolServerID: Int64, userID: Int64) async throws {
        guard let token = deviceToken() else { return }
        let page: PaginatedResponse<ProtocolRatingDTO> = try await apiClient.get(
            "ratings/",
            query: [
                URLQueryItem(name: "protocol", value: String(protocolServerID)),
                URLQueryItem(name: "user", value: String(userID)),
            ],
            authorizationHeader: "DeviceToken \(token)"
        )
        guard let dto = page.results.first else { return }
        try await store.upsertSingle(dto)
    }

    @discardableResult
    public func rate(protocolServerID: Int64, userID: Int64, complexityRating: Int, durationRating: Int) async throws -> ProtocolRatingDTO {
        guard let token = deviceToken() else {
            throw ProtocolRatingSyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"

        let existing: PaginatedResponse<ProtocolRatingDTO> = try await apiClient.get(
            "ratings/",
            query: [
                URLQueryItem(name: "protocol", value: String(protocolServerID)),
                URLQueryItem(name: "user", value: String(userID)),
            ],
            authorizationHeader: authorization
        )

        let dto: ProtocolRatingDTO
        if let existingRating = existing.results.first {
            dto = try await apiClient.send(
                "ratings/\(existingRating.id)/",
                method: .patch,
                body: RateProtocolRequest(protocolServerID: protocolServerID, complexityRating: complexityRating, durationRating: durationRating),
                authorizationHeader: authorization
            )
        } else {
            dto = try await apiClient.send(
                "ratings/",
                method: .post,
                body: RateProtocolRequest(protocolServerID: protocolServerID, complexityRating: complexityRating, durationRating: durationRating),
                authorizationHeader: authorization
            )
        }
        try await store.upsertSingle(dto)
        return dto
    }
}

public enum ProtocolRatingSyncError: Error {
    case noDeviceToken
}

actor ProtocolRatingStore {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func upsertSingle(_ dto: ProtocolRatingDTO) throws {
        let protocolServerID = dto.protocol_
        if let existing = try modelContext.fetch(FetchDescriptor<CachedProtocolRating>(predicate: #Predicate { $0.protocolServerID == protocolServerID })).first {
            existing.serverID = dto.id
            existing.complexityRating = dto.complexityRating
            existing.durationRating = dto.durationRating
        } else {
            modelContext.insert(CachedProtocolRating(
                protocolServerID: dto.protocol_,
                serverID: dto.id,
                complexityRating: dto.complexityRating,
                durationRating: dto.durationRating
            ))
        }
        try modelContext.save()
    }
}
