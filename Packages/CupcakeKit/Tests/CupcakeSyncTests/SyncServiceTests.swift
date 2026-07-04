import Foundation
import SwiftData
import Testing

@testable import CupcakeModels
@testable import CupcakeNetworking
@testable import CupcakeSync

/// One suite, not several — `StubURLProtocol.handler` is shared mutable state, and Swift Testing
/// parallelizes across *sibling* suites by default even though `.serialized` keeps a single
/// suite's own tests from racing each other. Splitting these across suites caused exactly that:
/// one test's response body served to another test's request. All tests touching the stub live
/// in this one serialized suite instead.
@Suite("CupcakeSync services", .serialized)
struct SyncServiceTests {
    private func makeInMemoryContainer(for types: [any PersistentModel.Type]) throws -> ModelContainer {
        let schema = Schema(types)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("refetchAll upserts protocols, sections, and steps from a paginated response")
    func refetchAllPopulatesStore() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {
                "count": 1, "next": null, "previous": null,
                "results": [{
                    "id": 42,
                    "protocol_title": "Sample prep",
                    "protocol_description": "Prepare the sample.",
                    "enabled": true,
                    "sections": [{
                        "id": 1, "section_description": "Setup", "order": 0,
                        "steps": [{"id": 10, "step_description": "Put on gloves", "order": 0}]
                    }]
                }]
            }
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchAll()

        let context = ModelContext(container)
        let protocols = try context.fetch(FetchDescriptor<CachedProtocol>())
        #expect(protocols.count == 1)
        #expect(protocols.first?.protocolTitle == "Sample prep")
        #expect(protocols.first?.sections.first?.steps.first?.stepDescription == "Put on gloves")
    }

    @Test("refetchAll is a no-op without a stored device token")
    func refetchAllNoOpWithoutToken() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("should not make a network request without a device token")
            throw URLError(.badURL)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { nil })

        try await service.refetchAll()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<CachedProtocol>()).isEmpty)
    }

    @Test("createSession posts and caches the returned Session")
    func createSessionCachesResult() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "DeviceToken test-token")
            let json = Data("""
            {
                "id": 7, "unique_id": "3f9c1f2e-1234-4a5b-8c6d-abcdef012345", "name": "Run 1",
                "enabled": true, "processing": false, "started_at": null, "ended_at": null,
                "is_running": false, "status": "ready", "protocols": []
            }
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.createSession(name: "Run 1")

        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<CachedSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.name == "Run 1")
        #expect(sessions.first?.serverID == 7)
    }

    @Test("createSession throws without a stored device token, without making a request")
    func createSessionRequiresDeviceToken() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("should not make a network request without a device token")
            throw URLError(.badURL)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { nil })

        await #expect(throws: SessionSyncError.self) {
            try await service.createSession(name: "Run 1")
        }
    }

    @Test("createTextAnnotation posts via the annotation_data shortcut when both session and step have a serverID")
    func createTextAnnotationOnlinePath() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {
                "id": 100, "session": 7, "step": 10, "annotation": 55,
                "annotation_text": "Gloves are on.", "annotation_type": "text", "order": 0
            }
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let step = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(session)
        context.insert(step)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.createTextAnnotation(sessionClientID: session.clientID, stepClientID: step.clientID, text: "Gloves are on.")

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.count == 1)
        #expect(annotations.first?.annotationText == "Gloves are on.")
        #expect(annotations.first?.serverID == 100)
    }

    @Test("createTextAnnotation falls back to a local-only insert without a serverID or device token")
    func createTextAnnotationLocalOnlyPath() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("should not make a network request when session/step have no serverID")
            throw URLError(.badURL)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let context = ModelContext(container)
        // No serverID on either — the standalone-mode case.
        let session = CachedSession(name: "Local Run", enabled: true, isRunning: true, status: "running")
        let step = CachedProtocolStep(stepDescription: "Put on gloves", order: 0)
        context.insert(session)
        context.insert(step)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { nil })

        try await service.createTextAnnotation(sessionClientID: session.clientID, stepClientID: step.clientID, text: "Local note.")

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.count == 1)
        #expect(annotations.first?.annotationText == "Local note.")
        #expect(annotations.first?.serverID == nil)
        #expect(annotations.first?.sessionClientID == session.clientID)
        #expect(annotations.first?.stepClientID == step.clientID)
    }

    @Test("InventorySyncService refetches storage objects, reagents, and stored reagents")
    func inventorySyncRefetchesAllThree() async throws {
        StubURLProtocol.handler = { request in
            let path = request.url!.path
            let json: Data
            if path.hasSuffix("storage-objects") {
                json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":1,"object_type":"freezer","object_name":"Freezer A","object_description":"-80C","stored_at":null}]}"#.utf8)
            } else if path.hasSuffix("/reagents") {
                json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":2,"name":"NaCl","unit":"g"}]}"#.utf8)
            } else {
                json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":5,"reagent":2,"reagent_name":"NaCl","reagent_unit":"g","storage_object":1,"storage_object_name":"Freezer A","quantity":100.0,"current_quantity":87.5,"barcode":null,"expiration_date":null,"low_stock_threshold":10.0}]}"#.utf8)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStorageObject.self, CachedReagent.self, CachedStoredReagent.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchStorageObjects()
        try await service.refetchReagents()
        try await service.refetchStoredReagents()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<CachedStorageObject>()).first?.objectName == "Freezer A")
        #expect(try context.fetch(FetchDescriptor<CachedReagent>()).first?.name == "NaCl")
        #expect(try context.fetch(FetchDescriptor<CachedStoredReagent>()).first?.currentQuantity == 87.5)
    }

    @Test("InstrumentSyncService refetches instruments and instrument usage")
    func instrumentSyncRefetchesBoth() async throws {
        StubURLProtocol.handler = { request in
            let path = request.url!.path
            let json: Data
            if path.hasSuffix("instruments") {
                json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":1,"instrument_name":"Mass Spec 1","instrument_description":"Orbitrap","enabled":true,"accepts_bookings":true,"allow_overlapping_bookings":false,"maintenance_overdue":false}]}"#.utf8)
            } else {
                json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":1,"instrument":1,"instrument_name":"Mass Spec 1","time_started":null,"time_ended":null,"usage_hours":null,"description":"Run","approved":false,"maintenance":false}]}"#.utf8)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedInstrument.self, CachedInstrumentUsage.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchInstruments()
        try await service.refetchInstrumentUsage()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<CachedInstrument>()).first?.instrumentName == "Mass Spec 1")
        #expect(try context.fetch(FetchDescriptor<CachedInstrumentUsage>()).first?.usageDescription == "Run")
    }

    @Test("SessionAnnotationSyncService refetches and caches session annotations")
    func sessionAnnotationSyncRefetches() async throws {
        StubURLProtocol.handler = { request in
            let json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":9,"session":7,"annotation_text":"Note","annotation_type":"text","order":0}]}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(session)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchAll()

        let annotations = try context.fetch(FetchDescriptor<CachedSessionAnnotation>())
        #expect(annotations.first?.annotationText == "Note")
        #expect(annotations.first?.sessionClientID == session.clientID)
    }

    @Test("SessionAnnotationSyncService skips annotations whose session isn't cached yet")
    func sessionAnnotationSyncSkipsUnresolvedSession() async throws {
        StubURLProtocol.handler = { request in
            let json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":9,"session":999,"annotation_text":"Note","annotation_type":"text","order":0}]}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchAll()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<CachedSessionAnnotation>()).isEmpty)
    }

    @Test("StepReagentSyncService resolves stepClientID from a cached step and upserts the nested reagent")
    func stepReagentSyncResolvesAndUpserts() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"count":1,"next":null,"previous":null,"results":[{
                "id": 1, "step": 10, "reagent": {"id": 2, "name": "NaCl", "unit": "g"},
                "quantity": 5.0, "scalable": false, "scalable_factor": 1.0
            }]}
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocolStep.self, CachedReagent.self, CachedStepReagent.self])
        let context = ModelContext(container)
        let step = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(step)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchAll()

        let stepReagents = try context.fetch(FetchDescriptor<CachedStepReagent>())
        #expect(stepReagents.count == 1)
        #expect(stepReagents.first?.stepClientID == step.clientID)
        #expect(stepReagents.first?.quantity == 5.0)

        let reagents = try context.fetch(FetchDescriptor<CachedReagent>())
        #expect(reagents.first?.name == "NaCl")
        #expect(stepReagents.first?.reagentClientID == reagents.first?.clientID)
    }

    @Test("StepReagentSyncService skips step-reagents whose step isn't cached yet")
    func stepReagentSyncSkipsUnresolvedStep() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"count":1,"next":null,"previous":null,"results":[{
                "id": 1, "step": 999, "reagent": {"id": 2, "name": "NaCl", "unit": "g"},
                "quantity": 5.0, "scalable": false, "scalable_factor": 1.0
            }]}
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocolStep.self, CachedReagent.self, CachedStepReagent.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchAll()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<CachedStepReagent>()).isEmpty)
    }

    @Test("OutboxService replays a queued createProtocol and attaches serverID to the existing local record")
    func outboxReplaySucceeds() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"id": 77, "protocol_title": "Sample Prep", "protocol_description": null, "enabled": false, "sections": []}
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        try context.save()
        let clientID = localProtocol.clientID

        try await outbox.enqueueCreateProtocol(clientID: clientID, title: "Sample Prep", description: nil, enabled: false)
        await outbox.replayPending()

        let protocols = try context.fetch(FetchDescriptor<CachedProtocol>())
        #expect(protocols.count == 1, "replay should attach a serverID to the existing local record, not insert a duplicate")
        #expect(protocols.first?.clientID == clientID)
        #expect(protocols.first?.serverID == 77)

        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty, "a successfully-replayed entry should be removed from the outbox")
    }

    @Test("OutboxService leaves a queued entry pending and bumps retryCount on a transport failure")
    func outboxReplayRetriesOnTransportFailure() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        try context.save()

        try await outbox.enqueueCreateProtocol(clientID: localProtocol.clientID, title: "Sample Prep", description: nil, enabled: false)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "a transport failure should leave the entry queued for a future retry, not drop it")
        #expect(entries.first?.retryCount == 1)
        #expect(entries.first?.status == OutboxEntryStatus.pending.rawValue)

        let protocols = try context.fetch(FetchDescriptor<CachedProtocol>())
        #expect(protocols.first?.serverID == nil, "no serverID should be attached until a replay actually succeeds")
    }
}
