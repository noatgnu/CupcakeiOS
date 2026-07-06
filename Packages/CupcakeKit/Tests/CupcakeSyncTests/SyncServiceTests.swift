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

    @Test("uploadAudioAnnotation posts a multipart chunked upload then PATCHes the on-device transcription")
    func uploadAudioAnnotationUploadsThenPatches() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/upload/step-annotation-chunks") {
                #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
                let json = Data("""
                {"annotation_id": 200, "step_annotation_id": 300, "message": "ok"}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(request.url!.path.hasSuffix("/step-annotations/300"))
            #expect(request.httpMethod == "PATCH")
            let json = Data("""
            {"id": 300, "session": 7, "step": 10, "annotation": 200,
             "annotation_text": "", "annotation_type": "audio", "order": 0,
             "transcribed": true, "transcription": "Gloves are on.", "language": "en-US", "translation": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02]).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let clientID = try await service.uploadAudioAnnotation(
            sessionServerID: 7,
            stepServerID: 10,
            sessionClientID: UUID(),
            stepClientID: UUID(),
            fileURL: tempFile,
            transcription: "Gloves are on.",
            language: "en-US",
            translation: nil
        )

        let inserted = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(inserted.first?.serverID == 300)
        #expect(inserted.first?.transcription == "Gloves are on.")
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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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

    @Test("OutboxService replays a project then its instrument job in FIFO order, resolving the job's parent dependency")
    func outboxReplayResolvesInstrumentJobAfterItsProject() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/projects") {
                let json = Data("""
                {"id": 12, "project_name": "Proteomics Study", "project_description": null}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else {
                let json = Data("""
                {"id": 44, "job_name": "Run 1", "job_type": "analysis", "status": "draft",
                 "project": 12, "instrument": null, "submitted_at": null, "completed_at": null,
                 "staff": [], "staff_usernames": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
        }

        let container = try makeInMemoryContainer(for: [CachedProject.self, CachedInstrumentJob.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localProject = CachedProject(projectName: "Proteomics Study")
        context.insert(localProject)
        let localJob = CachedInstrumentJob(jobName: "Run 1", projectClientID: localProject.clientID)
        context.insert(localJob)
        try context.save()

        try await outbox.enqueueCreateProject(clientID: localProject.clientID)
        try await outbox.enqueueCreateInstrumentJob(clientID: localJob.clientID)
        await outbox.replayPending()

        let projects = try context.fetch(FetchDescriptor<CachedProject>())
        #expect(projects.first?.serverID == 12)

        let jobs = try context.fetch(FetchDescriptor<CachedInstrumentJob>())
        #expect(jobs.count == 1, "replay should attach a serverID to the existing local job, not insert a duplicate")
        #expect(jobs.first?.serverID == 44)

        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService retries (not fails) an instrument job queued before its project has synced")
    func outboxReplayRetriesInstrumentJobWhoseProjectIsntSyncedYet() async throws {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let container = try makeInMemoryContainer(for: [CachedProject.self, CachedInstrumentJob.self, OutboxEntry.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localProject = CachedProject(projectName: "Proteomics Study")
        context.insert(localProject)
        let localJob = CachedInstrumentJob(jobName: "Run 1", projectClientID: localProject.clientID)
        context.insert(localJob)
        try context.save()

        try await outbox.enqueueCreateInstrumentJob(clientID: localJob.clientID)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "an unmet parent dependency should retry, not be dropped or marked failed")
        #expect(entries.first?.status == OutboxEntryStatus.pending.rawValue)
        #expect(entries.first?.retryCount == 1)

        let jobs = try context.fetch(FetchDescriptor<CachedInstrumentJob>())
        #expect(jobs.first?.serverID == nil)
    }

    @Test("InstrumentJobSyncService.submit posts to the submit action and updates the cached status")
    func instrumentJobSubmitUpdatesStatus() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/instrument-jobs/44/submit"))
            let json = Data("""
            {"id": 44, "job_name": "Run 1", "job_type": "analysis", "status": "submitted",
             "project": null, "instrument": null, "submitted_at": "2026-01-01T00:00:00Z", "completed_at": null,
             "staff": [], "staff_usernames": []}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProject.self, CachedInstrumentJob.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let context = ModelContext(container)
        let job = CachedInstrumentJob(serverID: 44, jobName: "Run 1", status: "draft")
        context.insert(job)
        try context.save()

        let dto = try await instrumentJobSync.submit(jobServerID: 44)
        #expect(dto.status == "submitted")

        let jobs = try context.fetch(FetchDescriptor<CachedInstrumentJob>())
        #expect(jobs.first?.status == "submitted")
        #expect(jobs.first?.submittedAt != nil)
    }

    @Test("InstrumentJobAnnotationSyncService.createBookingAnnotation sets the job's instrument before booking, or the server-side merge signal silently never fires")
    func createBookingAnnotationSetsInstrumentFirst() async throws {
        // Confirmed live against a real backend: `merge_instrument_metadata_on_booking`
        // (`ccm/signals.py`) bails out immediately if `instrument_job.instrument` is unset — and
        // nothing else in the booking sequence ever sets it. Every other call in this sequence
        // succeeds regardless, making this the one call whose absence is a silent no-op, not an
        // error — this test exists specifically to make that ordering a regression, not just a
        // one-off manual finding.
        nonisolated(unsafe) var sawInstrumentPatchBeforeUsagePost = false
        nonisolated(unsafe) var patchedInstrumentJobPath: String?

        StubURLProtocol.handler = { request in
            let path = request.url!.path
            if request.httpMethod == "PATCH", path.hasSuffix("/instrument-jobs/77") {
                patchedInstrumentJobPath = path
                let json = Data("""
                {"id": 77, "job_name": "Run 1", "job_type": "analysis", "status": "draft",
                 "project": 1, "instrument": 5, "submitted_at": null, "completed_at": null,
                 "staff": [], "staff_usernames": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            } else if request.httpMethod == "POST", path.hasSuffix("/instrument-usage") {
                sawInstrumentPatchBeforeUsagePost = patchedInstrumentJobPath != nil
                let json = Data("""
                {"id": 9, "instrument": 5, "instrument_name": "Test Centrifuge",
                 "time_started": "2026-07-06T10:00:00Z", "time_ended": "2026-07-06T11:00:00Z",
                 "description": "test booking", "approved": true, "maintenance": false}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else if request.httpMethod == "POST", path.hasSuffix("/instrument-job-annotations") {
                let json = Data("""
                {"id": 3, "instrument_job": 77, "annotation_text": "Instrument booking for Test Centrifuge",
                 "annotation_type": "booking", "role": "staff", "order": 0}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else if request.httpMethod == "POST", path.hasSuffix("/instrument-usage-job-annotations") {
                let json = Data("""
                {"id": 1, "instrument_job_annotation": 3, "instrument_usage": 9}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else if request.httpMethod == "GET", path.hasSuffix("/instrument-jobs/77") {
                let json = Data("""
                {"id": 77, "job_name": "Run 1", "job_type": "analysis", "status": "draft",
                 "project": 1, "instrument": 5, "submitted_at": null, "completed_at": null, "metadata_table": 12,
                 "staff": [], "staff_usernames": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            } else {
                let json = Data("""
                {"id": 12, "name": "Run 1 - Metadata", "description": null, "sample_count": 1,
                 "version": "1.0", "owner_username": "testuser", "lab_group_name": null,
                 "is_published": false, "can_edit": true,
                 "columns": [{"id": 1, "name": "Serial Number", "display_name": "Serial Number",
                              "type": "characteristics", "column_position": 0, "value": "SN-12345",
                              "not_applicable": false, "not_available": false, "mandatory": false, "hidden": false,
                              "readonly": false, "ontology_type": null, "staff_only": false}]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
        }

        let container = try makeInMemoryContainer(for: [CachedInstrumentJob.self, CachedInstrumentJobAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobAnnotationSync = InstrumentJobAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" }, instrumentJobSync: instrumentJobSync)

        let mergedTable = try await instrumentJobAnnotationSync.createBookingAnnotation(
            jobServerID: 77,
            jobClientID: UUID(),
            instrumentServerID: 5,
            instrumentName: "Test Centrifuge",
            timeStarted: "2026-07-06T10:00:00Z",
            timeEnded: "2026-07-06T11:00:00Z",
            usageDescription: "test booking"
        )

        #expect(patchedInstrumentJobPath != nil, "the job's instrument must be PATCHed as part of booking, or the merge signal never fires")
        #expect(sawInstrumentPatchBeforeUsagePost, "the instrument PATCH must happen before the booking sequence, not after")
        #expect(mergedTable?.columns.first?.name == "Serial Number")
    }

    @Test("LabGroupSyncService.fetchMembers requests direct members only")
    func fetchMembersRequestsDirectOnly() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/lab-groups/1/members"))
            #expect(request.url!.query?.contains("direct_only=true") == true)
            let json = Data("""
            {"count": 1, "next": null, "previous": null, "results": [
                {"id": 1, "username": "testuser", "first_name": "", "last_name": ""}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedLabGroup.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let labGroupSync = LabGroupSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let members = try await labGroupSync.fetchMembers(labGroupServerID: 1)
        #expect(members.count == 1)
        #expect(members.first?.username == "testuser")
    }

    @Test("InstrumentJobSyncService.updateStaff PATCHes the job's staff list and updates the cache")
    func updateStaffPatchesJob() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/instrument-jobs/88"))
            let json = Data("""
            {"id": 88, "job_name": "Run 2", "job_type": "analysis", "status": "draft",
             "project": null, "instrument": null, "submitted_at": null, "completed_at": null,
             "lab_group": 1, "staff": [1], "staff_usernames": ["testuser"]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedInstrumentJob.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let context = ModelContext(container)
        let job = CachedInstrumentJob(serverID: 88, jobName: "Run 2", status: "draft")
        context.insert(job)
        try context.save()

        let dto = try await instrumentJobSync.updateStaff(jobServerID: 88, staffServerIDs: [1])
        #expect(dto.staffUsernames == ["testuser"])

        let jobs = try context.fetch(FetchDescriptor<CachedInstrumentJob>())
        #expect(jobs.first?.staffServerIDs == [1])
        #expect(jobs.first?.staffUsernames == ["testuser"])
    }

    @Test("MetadataColumnSyncService.updateColumnValue POSTs the value and updates the cached column in place")
    func updateColumnValueUpdatesCache() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/metadata-columns/5/update_column_value"))
            let json = Data("""
            {"message": "Column value updated successfully", "value_type": "default",
             "changes": {}, "column": {"id": 5, "name": "Serial Number", "display_name": "Serial Number",
             "type": "characteristics", "column_position": 0, "value": "SN-99999",
             "not_applicable": false, "not_available": false, "mandatory": false, "hidden": false,
             "readonly": false, "ontology_type": null, "staff_only": false}}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let context = ModelContext(container)
        let column = CachedMetadataColumn(serverID: 5, metadataTableServerID: 3, name: "Serial Number", type: "characteristics", value: "SN-12345")
        context.insert(column)
        try context.save()

        let dto = try await metadataColumnSync.updateColumnValue(columnServerID: 5, value: "SN-99999")
        #expect(dto.value == "SN-99999")

        let columns = try context.fetch(FetchDescriptor<CachedMetadataColumn>())
        #expect(columns.first?.value == "SN-99999")
    }

    @Test("MetadataColumnSyncService.fetchOntologySuggestions requests suggestions scoped to the column")
    func fetchOntologySuggestionsScopesToColumn() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/metadata-columns/ontology_suggestions"))
            #expect(request.url!.query?.contains("column_id=5") == true)
            let json = Data("""
            {"ontology_type": "species", "suggestions": [
                {"id": "9606", "value": "Homo sapiens", "display_name": "Homo sapiens",
                 "description": "Homo sapiens", "ontology_type": "species"}
            ], "search_term": "homo", "search_type": "icontains", "limit": 10, "count": 1,
             "custom_filters": {}, "has_more": false}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let suggestions = try await metadataColumnSync.fetchOntologySuggestions(columnServerID: 5, search: "homo")
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.displayName == "Homo sapiens")
    }

    @Test("MetadataColumnSyncService.fetchOntologySuggestions returns empty for a search under 2 characters, without a network call")
    func fetchOntologySuggestionsSkipsShortSearch() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("should not make a network call for a search under 2 characters")
            throw URLError(.badServerResponse)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let suggestions = try await metadataColumnSync.fetchOntologySuggestions(columnServerID: 5, search: "h")
        #expect(suggestions.isEmpty)
    }

    @Test("FavouriteMetadataOptionSyncService.fetchPersonalFavourites filters by user_id and column name")
    func fetchPersonalFavouritesFiltersByUser() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/favourite-options"))
            #expect(request.url!.query?.contains("user_id=1") == true)
            #expect(request.url!.query?.contains("name=Serial") == true)
            let json = Data("""
            {"count": 1, "next": null, "previous": null, "results": [
                {"id": 4, "name": "Serial Number", "type": "characteristics", "column_template": null,
                 "value": "SN-PERSONAL2", "display_value": "SN-PERSONAL2", "user": 1, "user_username": "testuser",
                 "lab_group": null, "is_global": false}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let favouriteSync = FavouriteMetadataOptionSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let favourites = try await favouriteSync.fetchPersonalFavourites(columnName: "Serial Number", userID: 1)
        #expect(favourites.count == 1)
        #expect(favourites.first?.value == "SN-PERSONAL2")
    }

    @Test("FavouriteMetadataOptionSyncService.fetchPersonalFavourites with no columnName lists every favourite, not scoped to one column")
    func fetchPersonalFavouritesListsAllWithoutColumnName() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/favourite-options"))
            #expect(request.url!.query?.contains("user_id=1") == true)
            #expect(request.url!.query?.contains("name=") != true)
            let json = Data("""
            {"count": 2, "next": null, "previous": null, "results": [
                {"id": 4, "name": "Serial Number", "type": "characteristics", "column_template": null,
                 "value": "SN-PERSONAL2", "display_value": "SN-PERSONAL2", "user": 1, "user_username": "testuser",
                 "lab_group": null, "is_global": false},
                {"id": 5, "name": "Organism", "type": "characteristics", "column_template": null,
                 "value": "Homo sapiens", "display_value": "Homo sapiens", "user": 1, "user_username": "testuser",
                 "lab_group": null, "is_global": false}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let favouriteSync = FavouriteMetadataOptionSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let favourites = try await favouriteSync.fetchPersonalFavourites(userID: 1, limit: 100)
        #expect(favourites.count == 2)
    }

    @Test("FavouriteMetadataOptionSyncService.createFavourite POSTs exactly one scope field per the caller's request")
    func createFavouritePostsScope() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/favourite-options"))
            let json = Data("""
            {"id": 3, "name": "Serial Number", "type": "characteristics", "column_template": null,
             "value": "SN-GLOBAL", "display_value": "SN-GLOBAL", "user": null, "lab_group": null, "is_global": true}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let favouriteSync = FavouriteMetadataOptionSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await favouriteSync.createFavourite(
            CreateFavouriteMetadataOptionRequest(name: "Serial Number", type: "characteristics", value: "SN-GLOBAL", isGlobal: true)
        )
        #expect(dto.isGlobal)
        #expect(dto.value == "SN-GLOBAL")
    }

    @Test("InstrumentJobSyncService.fetchProjectColumnValues requests the project/column-scoped history endpoint")
    func fetchProjectColumnValuesRequestsCorrectQuery() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/instrument-jobs/project_column_values"))
            #expect(request.url!.query?.contains("project_id=1") == true)
            #expect(request.url!.query?.contains("column_name=Serial") == true)
            let json = Data("""
            {"values": ["SN-99999", "SN-12345"]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedInstrumentJob.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let values = try await instrumentJobSync.fetchProjectColumnValues(projectServerID: 1, columnName: "Serial Number")
        #expect(values == ["SN-99999", "SN-12345"])
    }

    @Test("MetadataColumnSyncService.fetchOntologySuggestions(ontologyType:customFilters:) hits the raw suggest endpoint with a JSON-encoded filter")
    func fetchOntologySuggestionsRawFallback() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/ontology/search/suggest"))
            #expect(request.url!.query?.contains("type=ms_unique_vocabularies") == true)
            #expect(request.url!.query?.contains("custom_filters=") == true)
            let json = Data("""
            {"ontology_type": "ms_unique_vocabularies", "suggestions": [
                {"id": "MS:1000449", "value": "MS:1000449", "display_name": "LTQ Orbitrap",
                 "description": "Finnigan LTQ Orbitrap MS.", "ontology_type": "ms_unique_vocabularies"}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let suggestions = try await metadataColumnSync.fetchOntologySuggestions(
            ontologyType: "ms_unique_vocabularies",
            customFilters: ["ms_unique_vocabularies": ["term_type": "instrument"]],
            search: "orbi"
        )
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.displayName == "LTQ Orbitrap")
    }

    @Test("MetadataColumnSyncService.addColumn posts column_data to add_column_with_auto_reorder")
    func addColumnPostsColumnData() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/metadata-tables/3/add_column_with_auto_reorder"))
            let json = Data("""
            {"message": "Column added", "column": {
                "id": 6, "name": "comment[acquisition date]", "display_name": "comment[acquisition date]",
                "type": "comment", "column_position": 1, "value": null, "not_applicable": false,
                "not_available": false, "mandatory": false, "hidden": false, "readonly": false,
                "ontology_type": null, "staff_only": false
            }}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let column = try await metadataColumnSync.addColumn(
            tableServerID: 3,
            columnData: AddColumnDataRequest(name: "comment[acquisition date]", type: "comment")
        )
        #expect(column.id == 6)
    }

    @Test("MetadataColumnSyncService.removeColumn posts column_id to remove_column")
    func removeColumnPostsColumnID() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/metadata-tables/3/remove_column"))
            let json = Data("""
            {"message": "Column removed successfully"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await metadataColumnSync.removeColumn(tableServerID: 3, columnServerID: 6)
    }

    @Test("MetadataColumnTemplateSyncService.search hits column-templates with a search query")
    func columnTemplateSearchRequestsCorrectQuery() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/column-templates"))
            #expect(request.url!.query?.contains("search=organism") == true)
            let json = Data("""
            {"count": 1, "next": null, "previous": null, "results": [
                {"id": 300, "name": "organism", "description": null, "column_name": "characteristics[organism]",
                 "column_type": "characteristics", "ontology_type": "species", "default_value": null,
                 "category": null, "is_system_template": true, "visibility": "public", "lab_group": null,
                 "can_edit": false, "can_delete": false}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataColumnTemplateSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let results = try await templateSync.search(query: "organism")
        #expect(results.count == 1)
        #expect(results.first?.columnName == "characteristics[organism]")
    }

    @Test("MetadataTableTemplateSyncService.createBlank posts a private template with no lab group")
    func createBlankTemplatePostsPrivateVisibility() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/metadata-table-templates"))
            let json = Data("""
            {"id": 10, "name": "New Blank", "description": null, "owner_username": "testuser",
             "visibility": "private", "is_default": false, "column_count": 0, "lab_group": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataTableTemplate.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataTableTemplateSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let template = try await templateSync.createBlank(name: "New Blank", description: nil, labGroupServerID: nil)
        #expect(template.id == 10)
        #expect(template.visibility == "private")
    }

    @Test("MetadataTableTemplateSyncService.createFromSchemas hits create_from_schema with schema names")
    func createFromSchemasRequestsCorrectPath() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/metadata-table-templates/create_from_schema"))
            let json = Data("""
            {"id": 11, "name": "From Schema", "description": null, "owner_username": "testuser",
             "visibility": "private", "is_default": false, "column_count": 9, "lab_group": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataTableTemplate.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataTableTemplateSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let template = try await templateSync.createFromSchemas(name: "From Schema", schemaNames: ["minimum"], description: nil, labGroupServerID: nil)
        #expect(template.id == 11)
        #expect(template.columnCount == 9)
    }

    @Test("MetadataColumnTemplateSyncService.myTemplates decodes a plain array response")
    func myTemplatesDecodesPlainArray() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/column-templates/my_templates"))
            let json = Data("""
            [{"id": 400, "name": "Mine", "description": null, "column_name": "characteristics[mine]",
              "column_type": "characteristics", "ontology_type": null, "default_value": null,
              "category": null, "is_system_template": false, "visibility": "private", "lab_group": null,
              "can_edit": true, "can_delete": true}]
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataColumnTemplateSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let templates = try await templateSync.myTemplates()
        #expect(templates.count == 1)
        #expect(templates.first?.canEdit == true)
    }

    @Test("MetadataColumnTemplateSyncService.create posts to column-templates")
    func createColumnTemplatePostsCorrectPath() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/column-templates"))
            let json = Data("""
            {"id": 401, "name": "New Template", "description": null, "column_name": "characteristics[new]",
             "column_type": "characteristics", "ontology_type": null, "default_value": null,
             "category": null, "is_system_template": false, "visibility": "private", "lab_group": null,
             "can_edit": true, "can_delete": true}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataColumnTemplateSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let template = try await templateSync.create(CreateColumnTemplateRequest(name: "New Template", columnName: "characteristics[new]", columnType: "characteristics"))
        #expect(template.id == 401)
    }

    @Test("MetadataColumnTemplateSyncService.delete hits DELETE on the template")
    func deleteColumnTemplateHitsCorrectPath() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/column-templates/401"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataColumnTemplateSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        try await templateSync.delete(templateServerID: 401)
    }
}
