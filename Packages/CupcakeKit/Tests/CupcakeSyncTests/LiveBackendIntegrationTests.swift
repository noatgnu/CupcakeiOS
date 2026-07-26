import Foundation
import SwiftData
import Testing

@testable import CupcakeAuth
@testable import CupcakeModels
@testable import CupcakeNetworking
@testable import CupcakeSync

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

        let login = try await authService.login(username: username, password: password)
        let deviceToken = try await authService.createDeviceToken(
            accessToken: login.accessToken,
            label: "iOS Integration Test (\(Date().description))"
        )
        let authorization = "DeviceToken \(deviceToken.token)"

        var createdSessionID: Int64?
        var bodyError: (any Error)?
        do {
            let schema = Schema([CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, CachedSession.self, CachedStepAnnotation.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { deviceToken.token })
            try await protocolSync.refetchAll()

            let context = ModelContext(container)
            let cachedProtocols = try context.fetch(FetchDescriptor<CachedProtocol>())

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
                    text: "iOS integration test annotation, safe to ignore/delete."
                )

                let cachedAnnotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
                #expect(cachedAnnotations.first?.annotationText == "iOS integration test annotation, safe to ignore/delete.")
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

    private static var isBookingMergeConfigured: Bool {
        let env = ProcessInfo.processInfo.environment
        return isConfigured
            && env["CUPCAKE_LIVE_TEST_INSTRUMENT_ID"] != nil
            && env["CUPCAKE_LIVE_TEST_TEMPLATE_ID"] != nil
            && env["CUPCAKE_LIVE_TEST_PROJECT_ID"] != nil
    }

    @Test(.enabled(if: LiveBackendIntegrationTests.isBookingMergeConfigured))
    func bookingMergesInstrumentMetadataOntoJob() async throws {
        let env = ProcessInfo.processInfo.environment
        let baseURL = try #require(URL(string: env["CUPCAKE_LIVE_TEST_BASE_URL"]!))
        let username = env["CUPCAKE_LIVE_TEST_USERNAME"]!
        let password = env["CUPCAKE_LIVE_TEST_PASSWORD"]!
        let instrumentServerID = try #require(Int64(env["CUPCAKE_LIVE_TEST_INSTRUMENT_ID"]!))
        let templateServerID = try #require(Int64(env["CUPCAKE_LIVE_TEST_TEMPLATE_ID"]!))
        let projectServerID = try #require(Int64(env["CUPCAKE_LIVE_TEST_PROJECT_ID"]!))

        let apiClient = APIClient(baseURL: baseURL)
        let authService = AuthService(apiClient: apiClient)
        let login = try await authService.login(username: username, password: password)
        let deviceToken = try await authService.createDeviceToken(
            accessToken: login.accessToken,
            label: "iOS Booking Merge Test (\(Date().description))"
        )
        let authorization = "DeviceToken \(deviceToken.token)"

        var createdJobServerID: Int64?
        var bodyError: (any Error)?
        do {
            let schema = Schema([CachedProject.self, CachedInstrumentJob.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let context = ModelContext(container)
            let project = CachedProject(serverID: projectServerID, projectName: "live test project")
            context.insert(project)
            let job = CachedInstrumentJob(jobName: "iOS Booking Merge Test \(Date().timeIntervalSince1970)", jobType: "analysis", projectClientID: project.clientID)
            context.insert(job)
            try context.save()

            let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { deviceToken.token })
            let jobServerID = try await instrumentJobSync.syncLocallyCreatedInstrumentJob(clientID: job.clientID)
            createdJobServerID = jobServerID

            try await instrumentJobSync.createMetadataFromTemplate(jobServerID: jobServerID, jobClientID: job.clientID, templateID: templateServerID)

            let annotationSync = InstrumentJobAnnotationSyncService(
                modelContainer: container,
                apiClient: apiClient,
                deviceToken: { deviceToken.token },
                instrumentJobSync: instrumentJobSync
            )
            let mergedTable = try await annotationSync.createBookingAnnotation(
                jobServerID: jobServerID,
                jobClientID: job.clientID,
                instrumentServerID: instrumentServerID,
                instrumentName: "Live test instrument",
                timeStarted: ISO8601DateFormatter().string(from: Date()),
                timeEnded: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
                usageDescription: "iOS booking-merge integration test"
            )

            let mergedColumns = try #require(mergedTable?.columns)
            #expect(mergedColumns.contains(where: { $0.value?.isEmpty == false }), "the instrument's own metadata should have merged at least one non-empty column onto the job")
        } catch {
            bodyError = error
        }

        if let createdJobServerID {
            try? await apiClient.sendNoContent("instrument-jobs/\(createdJobServerID)/", method: .delete, authorizationHeader: authorization)
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

    @Test(.enabled(if: LiveBackendIntegrationTests.isConfigured))
    func timeKeeperCrossDeviceEventArrivesOverWebSocket() async throws {
        let env = ProcessInfo.processInfo.environment
        let baseURL = try #require(URL(string: env["CUPCAKE_LIVE_TEST_BASE_URL"]!))
        let username = env["CUPCAKE_LIVE_TEST_USERNAME"]!
        let password = env["CUPCAKE_LIVE_TEST_PASSWORD"]!

        let apiClient = APIClient(baseURL: baseURL)
        let authService = AuthService(apiClient: apiClient)
        let login = try await authService.login(username: username, password: password)
        let deviceToken = try await authService.createDeviceToken(
            accessToken: login.accessToken,
            label: "iOS TimeKeeper WS Test (\(Date().description))"
        )
        let authorization = "DeviceToken \(deviceToken.token)"

        var createdSessionID: Int64?
        var bodyError: (any Error)?
        do {
            let schema = Schema([CachedSession.self, CachedTimeKeeper.self])
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { deviceToken.token })
            try await sessionSync.createSession(name: "iOS TimeKeeper WS Test \(Date().timeIntervalSince1970)")

            let context = ModelContext(container)
            let session = try #require(try context.fetch(FetchDescriptor<CachedSession>()).first)
            createdSessionID = session.serverID
            let sessionServerID = try #require(session.serverID)

            let notificationService = TimeKeeperNotificationService(apiClient: apiClient, deviceToken: { deviceToken.token })
            let events = await notificationService.subscribe()

            try await Task.sleep(for: .seconds(1))

            let timeKeeperSync = TimeKeeperSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { deviceToken.token })
            let timeKeeperServerID = try await timeKeeperSync.create(
                sessionServerID: sessionServerID, sessionClientID: session.clientID,
                stepServerID: nil, stepClientID: nil, durationSeconds: 120
            )
            try await timeKeeperSync.startTimer(serverID: timeKeeperServerID)

            let receivedEvent = try await withThrowingTaskGroup(of: TimeKeeperNotificationService.Event?.self) { group in
                group.addTask {
                    for await event in events {
                        if case .started(let eventTimeKeeperServerID, _, _, _) = event, eventTimeKeeperServerID == timeKeeperServerID {
                            return event
                        }
                    }
                    return nil
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    return nil
                }
                let result = try await group.next() ?? nil
                group.cancelAll()
                return result
            }

            let event = try #require(receivedEvent, "expected a real timekeeper.started event over the WebSocket within 10s")
            #expect(event.sessionServerID == sessionServerID)
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
