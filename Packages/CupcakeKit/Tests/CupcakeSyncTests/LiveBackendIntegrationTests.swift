import Foundation
import SwiftData
import Testing

@testable import CupcakeAuth
@testable import CupcakeModels
@testable import CupcakeNetworking
@testable import CupcakeSync

/// Exercises the real backend contract end-to-end — login, DeviceToken provisioning, protocol
/// fetch, and (if a protocol/step exists to attach to) session + text-annotation creation.
/// Skipped unless `CUPCAKE_LIVE_TEST_BASE_URL`/`_USERNAME`/`_PASSWORD` are set, so it never runs
/// for a contributor without credentials and never blocks CI unless those secrets are configured.
/// Everything this test creates on the server (DeviceToken, Session, StepAnnotation) is deleted
/// again before the test returns, success or failure.
@Suite("Live backend integration", .serialized)
struct LiveBackendIntegrationTests {
    private static var isConfigured: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["CUPCAKE_LIVE_TEST_BASE_URL"] != nil
            && env["CUPCAKE_LIVE_TEST_USERNAME"] != nil
            && env["CUPCAKE_LIVE_TEST_PASSWORD"] != nil
    }

    @Test(.enabled(if: LiveBackendIntegrationTests.isConfigured))
    func loginFetchProtocolsAndCreateSessionWithAnnotation() async throws {
        let env = ProcessInfo.processInfo.environment
        let baseURL = try #require(URL(string: env["CUPCAKE_LIVE_TEST_BASE_URL"]!))
        let username = env["CUPCAKE_LIVE_TEST_USERNAME"]!
        let password = env["CUPCAKE_LIVE_TEST_PASSWORD"]!

        let apiClient = APIClient(baseURL: baseURL)
        let authService = AuthService(apiClient: apiClient)

        // 1. Login (JWT) -> DeviceToken exchange, exactly as AuthManager.signIn does.
        let login = try await authService.login(username: username, password: password)
        let deviceToken = try await authService.createDeviceToken(
            accessToken: login.accessToken,
            label: "iOS Integration Test (\(Date().description))"
        )
        let authorization = "DeviceToken \(deviceToken.token)"

        // Everything below is wrapped so cleanup always runs — awaited, not fire-and-forget —
        // before this function returns, whether the body below succeeds or throws. This is a
        // real production-adjacent account; leaking a Session or DeviceToken on a thrown
        // assertion would be a real, visible side effect for the user, not just a test artifact.
        var createdSessionID: Int64?
        var bodyError: (any Error)?
        do {
            // 2. Protocol fetch — read-only, exercises pagination + nested section/step decoding
            // against the real contract.
            let schema = Schema([CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, CachedSession.self, CachedStepAnnotation.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { deviceToken.token })
            try await protocolSync.refetchAll()

            let context = ModelContext(container)
            let cachedProtocols = try context.fetch(FetchDescriptor<CachedProtocol>())

            // 3. Session + text StepAnnotation creation — only if there's a real step to attach
            // to. This account may have zero protocols; that's a valid real-world state, not a
            // test failure, so this part is best-effort rather than a hard requirement.
            if let firstStep = cachedProtocols.flatMap(\.sections).flatMap(\.steps).first {
                let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { deviceToken.token })
                try await sessionSync.createSession(name: "iOS Integration Test \(Date().timeIntervalSince1970)")

                let cachedSessions = try context.fetch(FetchDescriptor<CachedSession>())
                let session = try #require(cachedSessions.first)
                createdSessionID = session.serverID

                let annotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { deviceToken.token })
                try await annotationSync.createTextAnnotation(
                    sessionClientID: session.clientID,
                    stepClientID: firstStep.clientID,
                    text: "iOS integration test annotation — safe to ignore/delete."
                )

                let cachedAnnotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
                #expect(cachedAnnotations.first?.annotationText == "iOS integration test annotation — safe to ignore/delete.")
            }
        } catch {
            bodyError = error
        }

        if let createdSessionID {
            try? await apiClient.sendNoContent("sessions/\(createdSessionID)/", method: .delete, authorizationHeader: authorization)
        }
        try? await apiClient.sendNoContent(
            "device-tokens/\(deviceToken.id)/",
            method: .delete,
            authorizationHeader: "Bearer \(login.accessToken)"
        )

        if let bodyError {
            throw bodyError
        }
    }
}
