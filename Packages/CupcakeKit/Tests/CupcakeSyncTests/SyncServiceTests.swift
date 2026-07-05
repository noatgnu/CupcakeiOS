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

    @Test("createTextAnnotation always inserts locally, then syncLocallyCreatedTextAnnotation posts via the annotation_data shortcut")
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

        let clientID = try await service.createTextAnnotation(sessionClientID: session.clientID, stepClientID: step.clientID, text: "Gloves are on.")
        try await service.syncLocallyCreatedTextAnnotation(clientID: clientID)

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.count == 1, "sync should attach a serverID to the existing local record, not insert a duplicate")
        #expect(annotations.first?.annotationText == "Gloves are on.")
        #expect(annotations.first?.serverID == 100)
    }

    @Test("createTextAnnotation is always a local-only insert regardless of serverID/device token")
    func createTextAnnotationLocalOnlyPath() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("createTextAnnotation itself should never make a network request")
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
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

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

    @Test("OutboxService replays a protocol then its section in FIFO order, resolving the section's parent dependency")
    func outboxReplayResolvesSectionAfterItsProtocol() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/protocols") {
                let json = Data("""
                {"id": 77, "protocol_title": "Sample Prep", "protocol_description": null, "enabled": false, "sections": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else {
                let json = Data("""
                {"id": 5, "section_description": "Setup", "order": 0, "section_duration": null, "steps": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSection = CachedProtocolSection(sectionDescription: "Setup", order: 0, protocolModel: localProtocol)
        context.insert(localSection)
        try context.save()

        // Enqueued in creation order — the protocol first, then the section that depends on it.
        try await outbox.enqueueCreateProtocol(clientID: localProtocol.clientID, title: "Sample Prep", description: nil, enabled: false)
        try await outbox.enqueueCreateSection(clientID: localSection.clientID)
        await outbox.replayPending()

        let protocols = try context.fetch(FetchDescriptor<CachedProtocol>())
        #expect(protocols.first?.serverID == 77)

        let sections = try context.fetch(FetchDescriptor<CachedProtocolSection>())
        #expect(sections.count == 1, "replay should attach a serverID to the existing local section, not insert a duplicate")
        #expect(sections.first?.serverID == 5, "the section should resolve its parent's serverID within the same replay pass, since FIFO order processed the protocol first")

        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService retries (not fails) a section queued before its parent protocol has synced")
    func outboxReplayRetriesSectionWhoseParentIsntSyncedYet() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSection = CachedProtocolSection(sectionDescription: "Setup", order: 0, protocolModel: localProtocol)
        context.insert(localSection)
        try context.save()

        // Only the section's entry is queued (simulating: its own creation attempt failed and
        // got queued, but for whatever reason the protocol's own entry isn't there — e.g. it
        // synced in a previous, separate replay pass that this test doesn't model). The
        // dependency check must still key off the *local* protocol record's current serverID,
        // which is nil here, not assume the protocol is fine just because it has no entry.
        try await outbox.enqueueCreateSection(clientID: localSection.clientID)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "an unmet parent dependency should retry, not be dropped or marked failed")
        #expect(entries.first?.status == OutboxEntryStatus.pending.rawValue)
        #expect(entries.first?.retryCount == 1)

        let sections = try context.fetch(FetchDescriptor<CachedProtocolSection>())
        #expect(sections.first?.serverID == nil)
    }

    @Test("OutboxService leaves a queued entry pending and bumps retryCount on a transport failure")
    func outboxReplayRetriesOnTransportFailure() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

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

    @Test("OutboxService replays a session once its primary protocol has synced, in the same FIFO pass")
    func outboxReplayResolvesSessionAfterItsProtocol() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/protocols") {
                let json = Data("""
                {"id": 77, "protocol_title": "Sample Prep", "protocol_description": null, "enabled": false, "sections": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else {
                let json = Data("""
                {"id": 9, "unique_id": "abc", "name": "Run 1", "enabled": true, "processing": false,
                 "started_at": null, "ended_at": null, "is_running": null, "status": "ready", "protocols": [77]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, CachedSession.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSession = CachedSession(name: "Run 1", enabled: true, isRunning: true, status: "running", primaryProtocolClientID: localProtocol.clientID)
        context.insert(localSession)
        try context.save()

        try await outbox.enqueueCreateProtocol(clientID: localProtocol.clientID, title: "Sample Prep", description: nil, enabled: false)
        try await outbox.enqueueCreateSession(clientID: localSession.clientID)
        await outbox.replayPending()

        let sessions = try context.fetch(FetchDescriptor<CachedSession>())
        #expect(sessions.count == 1, "replay should attach a serverID to the existing local session, not insert a duplicate")
        #expect(sessions.first?.serverID == 9)

        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService retries (not fails) a session queued before its primary protocol has synced")
    func outboxReplayRetriesSessionWhoseParentIsntSyncedYet() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, CachedSession.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSession = CachedSession(name: "Run 1", enabled: true, isRunning: true, status: "running", primaryProtocolClientID: localProtocol.clientID)
        context.insert(localSession)
        try context.save()

        try await outbox.enqueueCreateSession(clientID: localSession.clientID)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "an unmet parent dependency should retry, not be dropped or marked failed")
        #expect(entries.first?.status == OutboxEntryStatus.pending.rawValue)
        #expect(entries.first?.retryCount == 1)

        let sessions = try context.fetch(FetchDescriptor<CachedSession>())
        #expect(sessions.first?.serverID == nil)
    }

    @Test("OutboxService replays a step-reagent once its step has synced, creating the new reagent inline")
    func outboxReplayResolvesStepReagentAfterItsStep() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/steps") {
                let json = Data("""
                {"id": 10, "step_description": "Mix", "order": 0, "step_duration": null}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else if request.url!.path.hasSuffix("/reagents") {
                let json = Data("""
                {"id": 3, "name": "NaCl", "unit": "g"}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else {
                let json = Data("""
                {"id": 20, "step": 10, "reagent": {"id": 3, "name": "NaCl", "unit": "g"},
                 "quantity": 5.0, "scalable": false, "scalable_factor": 1.0}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
        }

        let container = try makeInMemoryContainer(for: [CachedProtocolStep.self, CachedReagent.self, CachedStepReagent.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localStep = CachedProtocolStep(stepDescription: "Mix", order: 0, stepDuration: nil)
        context.insert(localStep)
        let localReagent = CachedReagent(name: "NaCl", unit: "g")
        context.insert(localReagent)
        let localStepReagent = CachedStepReagent(stepClientID: localStep.clientID, reagentClientID: localReagent.clientID, quantity: 5.0, scalable: false, scalableFactor: 1.0)
        context.insert(localStepReagent)
        try context.save()

        // Simulate the step already having synced in a prior pass — its own outbox entry isn't
        // modeled here since `ProtocolSyncService`'s own FIFO-ordering behavior is already
        // covered by the section/step tests above; this test is purely about the reagent's
        // inline creation and the step-reagent's own dependency check.
        localStep.serverID = 10
        try context.save()

        try await outbox.enqueueCreateStepReagent(clientID: localStepReagent.clientID)
        await outbox.replayPending()

        let reagents = try context.fetch(FetchDescriptor<CachedReagent>())
        #expect(reagents.count == 1, "the reagent should get a serverID attached in place, not be duplicated")
        #expect(reagents.first?.serverID == 3)

        let stepReagents = try context.fetch(FetchDescriptor<CachedStepReagent>())
        #expect(stepReagents.count == 1)
        #expect(stepReagents.first?.serverID == 20)

        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService retries (not fails) a step-reagent queued before its step has synced")
    func outboxReplayRetriesStepReagentWhoseStepIsntSyncedYet() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocolStep.self, CachedReagent.self, CachedStepReagent.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localStep = CachedProtocolStep(stepDescription: "Mix", order: 0, stepDuration: nil)
        context.insert(localStep)
        let localReagent = CachedReagent(name: "NaCl", unit: "g")
        context.insert(localReagent)
        let localStepReagent = CachedStepReagent(stepClientID: localStep.clientID, reagentClientID: localReagent.clientID, quantity: 5.0, scalable: false, scalableFactor: 1.0)
        context.insert(localStepReagent)
        try context.save()

        try await outbox.enqueueCreateStepReagent(clientID: localStepReagent.clientID)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "an unmet parent dependency should retry, not be dropped or marked failed")
        #expect(entries.first?.status == OutboxEntryStatus.pending.rawValue)
        #expect(entries.first?.retryCount == 1)

        let stepReagents = try context.fetch(FetchDescriptor<CachedStepReagent>())
        #expect(stepReagents.first?.serverID == nil)
    }

    @Test("OutboxService replays a text annotation once its session and step have synced")
    func outboxReplayResolvesTextAnnotationAfterItsSessionAndStep() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/protocols") {
                let json = Data("""
                {"id": 77, "protocol_title": "Sample Prep", "protocol_description": null, "enabled": false, "sections": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else if request.url!.path.hasSuffix("/sessions") {
                let json = Data("""
                {"id": 9, "unique_id": "abc", "name": "Run 1", "enabled": true, "processing": false,
                 "started_at": null, "ended_at": null, "is_running": null, "status": "ready", "protocols": [77]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else {
                let json = Data("""
                {"id": 100, "session": 9, "step": 10, "annotation": 55,
                 "annotation_text": "Gloves are on.", "annotation_type": "text", "order": 0}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, CachedSession.self, CachedStepAnnotation.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSession = CachedSession(name: "Run 1", enabled: true, isRunning: true, status: "running", primaryProtocolClientID: localProtocol.clientID)
        context.insert(localSession)
        let localStep = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(localStep)
        let localAnnotation = CachedStepAnnotation(sessionClientID: localSession.clientID, stepClientID: localStep.clientID, annotationText: "Gloves are on.", annotationType: "text", order: 0)
        context.insert(localAnnotation)
        try context.save()

        // Enqueued in creation order: protocol, then session (depends on it), then the
        // annotation (depends on the session — the step is already synced in this test).
        try await outbox.enqueueCreateProtocol(clientID: localProtocol.clientID, title: "Sample Prep", description: nil, enabled: false)
        try await outbox.enqueueCreateSession(clientID: localSession.clientID)
        try await outbox.enqueueCreateTextAnnotation(clientID: localAnnotation.clientID)
        await outbox.replayPending()

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.count == 1, "replay should attach a serverID to the existing local annotation, not insert a duplicate")
        #expect(annotations.first?.serverID == 100)

        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService retries (not fails) a text annotation queued before its session has synced")
    func outboxReplayRetriesTextAnnotationWhoseSessionIsntSyncedYet() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, CachedSession.self, CachedStepAnnotation.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localSession = CachedSession(name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(localSession)
        let localStep = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(localStep)
        let localAnnotation = CachedStepAnnotation(sessionClientID: localSession.clientID, stepClientID: localStep.clientID, annotationText: "Gloves are on.", annotationType: "text", order: 0)
        context.insert(localAnnotation)
        try context.save()

        try await outbox.enqueueCreateTextAnnotation(clientID: localAnnotation.clientID)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "an unmet parent dependency should retry, not be dropped or marked failed")
        #expect(entries.first?.status == OutboxEntryStatus.pending.rawValue)
        #expect(entries.first?.retryCount == 1)

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.first?.serverID == nil)
    }

    @Test("OutboxService replays a stored reagent once its reagent and storage object have synced")
    func outboxReplayResolvesStoredReagent() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"id": 30, "reagent": 3, "reagent_name": "NaCl", "reagent_unit": "g",
             "storage_object": 5, "storage_object_name": "Fridge A", "quantity": 100.0,
             "current_quantity": 100.0, "barcode": null, "expiration_date": null, "low_stock_threshold": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStorageObject.self, CachedReagent.self, CachedStoredReagent.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localStoredReagent = CachedStoredReagent(reagentServerID: 3, reagentName: "NaCl", reagentUnit: "g", storageObjectServerID: 5, storageObjectName: "Fridge A", quantity: 100.0, currentQuantity: 100.0)
        context.insert(localStoredReagent)
        try context.save()

        try await outbox.enqueueCreateStoredReagent(clientID: localStoredReagent.clientID)
        await outbox.replayPending()

        let storedReagents = try context.fetch(FetchDescriptor<CachedStoredReagent>())
        #expect(storedReagents.count == 1, "replay should attach a serverID to the existing local record, not insert a duplicate")
        #expect(storedReagents.first?.serverID == 30)
        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService retries (not fails) a stored reagent queued before its reagent has synced")
    func outboxReplayRetriesStoredReagentWhoseReagentIsntSyncedYet() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedStorageObject.self, CachedReagent.self, CachedStoredReagent.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        // No reagentServerID/storageObjectServerID set — the not-yet-synced case.
        let localStoredReagent = CachedStoredReagent(reagentName: "NaCl", reagentUnit: "g", storageObjectName: "Fridge A", quantity: 100.0, currentQuantity: 100.0)
        context.insert(localStoredReagent)
        try context.save()

        try await outbox.enqueueCreateStoredReagent(clientID: localStoredReagent.clientID)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "an unmet parent dependency should retry, not be dropped or marked failed")
        #expect(entries.first?.status == OutboxEntryStatus.pending.rawValue)
        #expect(entries.first?.retryCount == 1)
    }

    @Test("OutboxService replays a reagent action once its stored reagent has synced")
    func outboxReplayResolvesReagentAction() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"id": 55, "reagent": 30, "action_type": "add", "quantity": 10.0, "notes": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStoredReagent.self, CachedReagentAction.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localStoredReagent = CachedStoredReagent(serverID: 30, quantity: 100.0, currentQuantity: 100.0)
        context.insert(localStoredReagent)
        let localAction = CachedReagentAction(storedReagentClientID: localStoredReagent.clientID, actionType: "add", quantity: 10.0)
        context.insert(localAction)
        try context.save()

        try await outbox.enqueueCreateReagentAction(clientID: localAction.clientID)
        await outbox.replayPending()

        let actions = try context.fetch(FetchDescriptor<CachedReagentAction>())
        #expect(actions.count == 1)
        #expect(actions.first?.serverID == 55)
        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService retries (not fails) a reagent action queued before its stored reagent has synced")
    func outboxReplayRetriesReagentActionWhoseParentIsntSyncedYet() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedStoredReagent.self, CachedReagentAction.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localStoredReagent = CachedStoredReagent(quantity: 100.0, currentQuantity: 100.0)
        context.insert(localStoredReagent)
        let localAction = CachedReagentAction(storedReagentClientID: localStoredReagent.clientID, actionType: "add", quantity: 10.0)
        context.insert(localAction)
        try context.save()

        try await outbox.enqueueCreateReagentAction(clientID: localAction.clientID)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "an unmet parent dependency should retry, not be dropped or marked failed")
        #expect(entries.first?.retryCount == 1)
    }

    @Test("OutboxService replays an instrument usage booking")
    func outboxReplayResolvesInstrumentUsage() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"id": 8, "instrument": 4, "instrument_name": "Centrifuge", "time_started": "2026-01-01T10:00:00Z",
             "time_ended": null, "usage_hours": null, "description": "Spin down", "approved": false, "maintenance": false}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedInstrument.self, CachedInstrumentUsage.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync)

        let context = ModelContext(container)
        let localUsage = CachedInstrumentUsage(instrumentServerID: 4, instrumentName: "Centrifuge", timeStarted: "2026-01-01T10:00:00Z", usageDescription: "Spin down", approved: false, maintenance: false)
        context.insert(localUsage)
        try context.save()

        try await outbox.enqueueCreateInstrumentUsage(clientID: localUsage.clientID)
        await outbox.replayPending()

        let usages = try context.fetch(FetchDescriptor<CachedInstrumentUsage>())
        #expect(usages.count == 1, "replay should attach a serverID to the existing local record, not insert a duplicate")
        #expect(usages.first?.serverID == 8)
        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }
}
