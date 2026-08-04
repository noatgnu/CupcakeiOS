import Foundation
import SwiftData
import Testing

@testable import CupcakeAuth
@testable import CupcakeModels
@testable import CupcakeNetworking
@testable import CupcakeSync

extension InputStream {
    func readAllData() -> Data {
        var result = Data()
        open()
        defer { close() }
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while hasBytesAvailable {
            let read = self.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            result.append(buffer, count: read)
        }
        return result
    }
}

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

    @Test("createCalculatorAnnotation inserts locally with annotationType calculator, then syncLocallyCreatedCalculatorAnnotation posts annotation_type calculator (not the hardcoded 'text' the sync path used before generalizing)")
    func createThenSyncCalculatorAnnotationPostsCorrectType() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/step-annotations"))
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let annotationData = try #require(sentJSON["annotation_data"] as? [String: Any])
            #expect(annotationData["annotation_type"] as? String == "calculator", "regression check: the sync path must read the stored record's own annotationType, not hardcode \"text\"")
            let json = Data("""
            {
                "id": 101, "session": 7, "step": 10, "annotation": 56,
                "annotation_text": "[{\\"id\\":\\"calc-1\\",\\"inputPromptFirstValue\\":2,\\"inputPromptSecondValue\\":3,\\"operation\\":\\"+\\",\\"result\\":5,\\"timestamp\\":\\"2026-01-01T00:00:00.000Z\\"}]",
                "annotation_type": "calculator", "order": 0
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

        let historyJSON = "[{\"id\":\"calc-1\",\"inputPromptFirstValue\":2,\"inputPromptSecondValue\":3,\"operation\":\"+\",\"result\":5,\"timestamp\":\"2026-01-01T00:00:00.000Z\"}]"
        let clientID = try await service.createCalculatorAnnotation(sessionClientID: session.clientID, stepClientID: step.clientID, historyJSON: historyJSON)

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.annotationType == "calculator")
        #expect(beforeSync.first?.serverID == nil)

        try await service.syncLocallyCreatedCalculatorAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 101)
        #expect(afterSync.first?.annotationType == "calculator")
    }

    @Test("createMolarityCalculatorAnnotation inserts locally with annotationType mcalculator, then syncLocallyCreatedMolarityCalculatorAnnotation posts annotation_type mcalculator")
    func createThenSyncMolarityCalculatorAnnotationPostsCorrectType() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let annotationData = try #require(sentJSON["annotation_data"] as? [String: Any])
            #expect(annotationData["annotation_type"] as? String == "mcalculator")
            let json = Data("""
            {
                "id": 102, "session": 7, "step": 10, "annotation": 57,
                "annotation_text": "[]", "annotation_type": "mcalculator", "order": 0
            }
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
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

        let entry = MolarityHistoryEntry(
            data: ["concentration": .number(5), "concentrationUnit": .string("mM")],
            operationType: "dynamic",
            result: 12.5,
            calculatedField: "weight"
        )
        let historyJSON = String(data: try JSONEncoder().encode([entry]), encoding: .utf8)!
        let clientID = try await service.createMolarityCalculatorAnnotation(sessionClientID: session.clientID, stepClientID: step.clientID, historyJSON: historyJSON)

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.annotationType == "mcalculator")

        try await service.syncLocallyCreatedMolarityCalculatorAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 102)
    }

    @Test("MolarityHistoryEntry round-trips through JSON with mixed number/string data values, matching the reference app's heterogeneous data dictionary")
    func molarityHistoryEntryRoundTripsMixedDataTypes() throws {
        let entry = MolarityHistoryEntry(
            id: "molarity-1",
            data: [
                "concentration": .number(5.5),
                "concentrationUnit": .string("mM"),
                "molecularWeight": .null,
            ],
            operationType: "dynamic",
            result: 12.5,
            timestamp: "2026-01-01T00:00:00.000Z",
            calculatedField: "weight"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(MolarityHistoryEntry.self, from: data)
        #expect(decoded.data["concentration"]?.doubleValue == 5.5)
        #expect(decoded.data["concentrationUnit"]?.stringValue == "mM")
        #expect(decoded.data["molecularWeight"] == .null)
        #expect(decoded.operationType == "dynamic")
        #expect(decoded.calculatedField == "weight")
    }

    @Test("createBookingAnnotation makes the 3-call sequence in order (instrument-usage -> step-annotations -> instrument-usage-step-annotations) and inserts a locally-synced record")
    func createBookingAnnotationMakesThreeCallsInOrder() async throws {
        nonisolated(unsafe) var callOrder: [String] = []
        StubURLProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/instrument-usage") {
                callOrder.append("instrument-usage")
                let json = Data("""
                {"id": 40, "user": 1, "user_username": "testuser", "instrument": 5, "instrument_name": "Centrifuge",
                 "time_started": "2026-07-11T10:00:00Z", "time_ended": "2026-07-11T12:00:00Z", "usage_hours": "2.00",
                 "description": "Spin down", "approved": true, "maintenance": false, "approved_by": null,
                 "remote_id": null, "remote_host": null, "created_at": "2026-07-11T10:00:00Z", "updated_at": "2026-07-11T10:00:00Z"}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
            if path.hasSuffix("/step-annotations") {
                callOrder.append("step-annotations")
                let body = try #require(request.httpBodyStream).readAllData()
                let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let annotationData = try #require(sentJSON["annotation_data"] as? [String: Any])
                #expect(annotationData["annotation_type"] as? String == "booking")
                #expect(annotationData["annotation"] as? String == "Instrument booking: Centrifuge")
                let json = Data("""
                {"id": 60, "session": 7, "step": 10, "annotation": 61,
                 "annotation_text": "Instrument booking: Centrifuge", "annotation_type": "booking", "order": 0}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(path.hasSuffix("/instrument-usage-step-annotations"))
            callOrder.append("instrument-usage-step-annotations")
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["step_annotation"] as? Int64 == 60)
            #expect(sentJSON["instrument_usage"] as? Int64 == 40)
            let json = Data("""
            {"id": 1, "step_annotation": 60, "instrument_usage": 40}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let clientID = try await service.createBookingAnnotation(
            sessionServerID: 7,
            sessionClientID: UUID(),
            stepServerID: 10,
            stepClientID: UUID(),
            instrumentServerID: 5,
            instrumentName: "Centrifuge",
            timeStarted: "2026-07-11T10:00:00Z",
            timeEnded: "2026-07-11T12:00:00Z",
            usageDescription: "Spin down"
        )

        #expect(callOrder == ["instrument-usage", "step-annotations", "instrument-usage-step-annotations"])

        let annotations = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(annotations.first?.serverID == 60)
        #expect(annotations.first?.annotationType == "booking")
        #expect(annotations.first?.instrumentUsageServerID == 40)
    }

    @Test("createAudioAnnotation inserts a local record with no network call, then syncLocallyCreatedAudioAnnotation uploads and PATCHes it")
    func createThenSyncAudioAnnotationUploadsAndPatches() async throws {
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
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let step = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(session)
        context.insert(step)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02]).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let clientID = try await service.createAudioAnnotation(
            sessionClientID: session.clientID,
            stepClientID: step.clientID,
            recordedFileURL: tempFile,
            transcription: "Gloves are on.",
            language: "en-US",
            translation: nil
        )

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.serverID == nil, "createAudioAnnotation should insert locally with no serverID yet, before any network call")
        #expect(beforeSync.first?.pendingFileName != nil)

        try await service.syncLocallyCreatedAudioAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 300)
        #expect(afterSync.first?.transcription == "Gloves are on.")
        #expect(afterSync.first?.pendingFileName == nil, "the persisted audio file reference should be cleared once synced")
    }

    @Test("SessionAnnotationSyncService: createAudioAnnotation inserts a local record with no network call, then syncLocallyCreatedAudioAnnotation uploads and PATCHes it")
    func sessionCreateThenSyncAudioAnnotationUploadsAndPatches() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/upload/session-annotation-chunks") {
                #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
                let json = Data("""
                {"annotation_id": 400, "session_annotation_id": 500, "message": "ok"}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(request.url!.path.hasSuffix("/session-annotations/500"))
            #expect(request.httpMethod == "PATCH")
            let json = Data("""
            {"id": 500, "session": 7, "annotation_text": "", "annotation_type": "audio", "order": 0}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(session)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02]).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let clientID = try await service.createAudioAnnotation(
            sessionClientID: session.clientID,
            recordedFileURL: tempFile,
            transcription: "Session note.",
            language: "en-US",
            translation: nil
        )

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.serverID == nil)

        try await service.syncLocallyCreatedAudioAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 500)
        #expect(afterSync.first?.transcription == "Session note.")
        #expect(afterSync.first?.pendingFileName == nil)
    }

    @Test("createImageAnnotation inserts a local record with no network call, then syncLocallyCreatedImageAnnotation uploads it with annotation_type=image")
    func createThenSyncImageAnnotationUploads() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/upload/step-annotation-chunks"))
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
            let json = Data("""
            {"annotation_id": 200, "step_annotation_id": 300, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
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

        let clientID = try await service.createImageAnnotation(
            sessionClientID: session.clientID,
            stepClientID: step.clientID,
            imageData: Data([0xFF, 0xD8, 0xFF])
        )

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.serverID == nil, "createImageAnnotation should insert locally with no serverID yet, before any network call")
        #expect(beforeSync.first?.annotationType == "image")
        #expect(beforeSync.first?.pendingFileName != nil)

        try await service.syncLocallyCreatedImageAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 300)
        #expect(afterSync.first?.pendingFileName == nil, "the persisted image file reference should be cleared once synced")
    }

    @Test("SessionAnnotationSyncService: createImageAnnotation inserts a local record, then syncLocallyCreatedImageAnnotation uploads it")
    func sessionCreateThenSyncImageAnnotationUploads() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/upload/session-annotation-chunks"))
            let json = Data("""
            {"annotation_id": 400, "session_annotation_id": 500, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(session)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let clientID = try await service.createImageAnnotation(sessionClientID: session.clientID, imageData: Data([0xFF, 0xD8, 0xFF]))

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.serverID == nil)
        #expect(beforeSync.first?.annotationType == "image")

        try await service.syncLocallyCreatedImageAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 500)
        #expect(afterSync.first?.pendingFileName == nil)
    }

    @Test("createVideoAnnotation inserts a local record with no network call, then syncLocallyCreatedVideoAnnotation uploads it with annotation_type=video and a MIME type derived from its extension")
    func createThenSyncVideoAnnotationUploads() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/upload/step-annotation-chunks"))
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
            let json = Data("""
            {"annotation_id": 200, "step_annotation_id": 300, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
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

        let clientID = try await service.createVideoAnnotation(
            sessionClientID: session.clientID,
            stepClientID: step.clientID,
            videoData: Data([0x00, 0x00, 0x00, 0x18]),
            fileExtension: "mov"
        )

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.serverID == nil, "createVideoAnnotation should insert locally with no serverID yet, before any network call")
        #expect(beforeSync.first?.annotationType == "video")
        #expect(beforeSync.first?.pendingFileName?.hasSuffix(".mov") == true)

        try await service.syncLocallyCreatedVideoAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 300)
        #expect(afterSync.first?.pendingFileName == nil, "the persisted video file reference should be cleared once synced")
    }

    @Test("SessionAnnotationSyncService: createVideoAnnotation inserts a local record, then syncLocallyCreatedVideoAnnotation uploads it")
    func sessionCreateThenSyncVideoAnnotationUploads() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/upload/session-annotation-chunks"))
            let json = Data("""
            {"annotation_id": 400, "session_annotation_id": 500, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(session)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let clientID = try await service.createVideoAnnotation(
            sessionClientID: session.clientID,
            videoData: Data([0x00, 0x00, 0x00, 0x18]),
            fileExtension: "mp4"
        )

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.serverID == nil)
        #expect(beforeSync.first?.annotationType == "video")

        try await service.syncLocallyCreatedVideoAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 500)
        #expect(afterSync.first?.pendingFileName == nil)
    }

    @Test("StepAnnotationSyncService: createSketchAnnotation inserts a local record, then syncLocallyCreatedSketchAnnotation uploads it")
    func createThenSyncSketchAnnotationUploads() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/upload/step-annotation-chunks"))
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
            let json = Data("""
            {"annotation_id": 201, "step_annotation_id": 301, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
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

        let clientID = try await service.createSketchAnnotation(
            sessionClientID: session.clientID,
            stepClientID: step.clientID,
            sketchData: Data("{}".utf8)
        )

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.serverID == nil, "createSketchAnnotation should insert locally with no serverID yet, before any network call")
        #expect(beforeSync.first?.annotationType == "sketch")
        #expect(beforeSync.first?.pendingFileName?.hasSuffix(".json") == true)

        try await service.syncLocallyCreatedSketchAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 301)
        #expect(afterSync.first?.pendingFileName == nil, "the persisted sketch file reference should be cleared once synced")
    }

    @Test("SessionAnnotationSyncService: createSketchAnnotation inserts a local record, then syncLocallyCreatedSketchAnnotation uploads it")
    func sessionCreateThenSyncSketchAnnotationUploads() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/upload/session-annotation-chunks"))
            let json = Data("""
            {"annotation_id": 401, "session_annotation_id": 501, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(session)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let clientID = try await service.createSketchAnnotation(
            sessionClientID: session.clientID,
            sketchData: Data("{}".utf8)
        )

        let beforeSync = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(beforeSync.first?.serverID == nil)
        #expect(beforeSync.first?.annotationType == "sketch")

        try await service.syncLocallyCreatedSketchAnnotation(clientID: clientID)

        let afterSync = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == clientID }))
        #expect(afterSync.first?.serverID == 501)
        #expect(afterSync.first?.pendingFileName == nil)
    }

    @Test("StepAnnotationSyncService: setScratched PATCHes scratched and updates the local record")
    func stepAnnotationSetScratchedUpdatesLocally() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/step-annotations/55"))
            let json = Data("""
            {"id": 55, "session": 7, "step": 10, "annotation": 200, "annotation_text": "Gloves on", "annotation_type": "text", "order": 0, "scratched": true}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let step = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        let annotation = CachedStepAnnotation(serverID: 55, sessionClientID: session.clientID, stepClientID: step.clientID, annotationText: "Gloves on", annotationType: "text")
        context.insert(session)
        context.insert(step)
        context.insert(annotation)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.setScratched(clientID: annotation.clientID, scratched: true)

        let annotationClientID = annotation.clientID
        let refetched = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == annotationClientID }))
        #expect(refetched.first?.scratched == true)
    }

    @Test("StepAnnotationSyncService: deleteAnnotation DELETEs and removes the local record")
    func stepAnnotationDeleteRemovesLocally() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/step-annotations/55"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let step = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        let annotation = CachedStepAnnotation(serverID: 55, sessionClientID: session.clientID, stepClientID: step.clientID, annotationText: "Gloves on", annotationType: "text")
        context.insert(session)
        context.insert(step)
        context.insert(annotation)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.deleteAnnotation(clientID: annotation.clientID)

        let annotationClientID = annotation.clientID
        let refetched = try ModelContext(container).fetch(FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == annotationClientID }))
        #expect(refetched.isEmpty)
    }

    @Test("SessionAnnotationSyncService: setScratched PATCHes scratched and updates the local record")
    func sessionAnnotationSetScratchedUpdatesLocally() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/session-annotations/66"))
            let json = Data("""
            {"id": 66, "session": 7, "annotation_text": "Note", "annotation_type": "text", "order": 0, "scratched": true}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let annotation = CachedSessionAnnotation(serverID: 66, sessionClientID: session.clientID, annotationText: "Note", annotationType: "text")
        context.insert(session)
        context.insert(annotation)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.setScratched(clientID: annotation.clientID, scratched: true)

        let annotationClientID = annotation.clientID
        let refetched = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == annotationClientID }))
        #expect(refetched.first?.scratched == true)
    }

    @Test("SessionAnnotationSyncService: deleteAnnotation DELETEs and removes the local record")
    func sessionAnnotationDeleteRemovesLocally() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/session-annotations/66"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let annotation = CachedSessionAnnotation(serverID: 66, sessionClientID: session.clientID, annotationText: "Note", annotationType: "text")
        context.insert(session)
        context.insert(annotation)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.deleteAnnotation(clientID: annotation.clientID)

        let annotationClientID = annotation.clientID
        let refetched = try ModelContext(container).fetch(FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.clientID == annotationClientID }))
        #expect(refetched.isEmpty)
    }

    @Test("StepAnnotationSyncService: downloadFile fetches a fresh detail record, then downloads the file's bytes and suggested filename")
    func stepAnnotationDownloadFileFetchesDetailThenBytes() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/step-annotations/55") {
                let json = Data("""
                {"id": 55, "session": 7, "step": 10, "annotation": 200, "annotation_text": "Uploaded file: tiny.jpg", "annotation_type": "image", "order": 0, "scratched": false, "file_url": "https://example.test/api/v1/annotations/200/download/?token=abc"}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            let headers = ["Content-Disposition": "attachment; filename=\"tiny.jpg\""]
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, Data([0xFF, 0xD8, 0xFF]))
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let step = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        let annotation = CachedStepAnnotation(serverID: 55, sessionClientID: session.clientID, stepClientID: step.clientID, annotationText: "Uploaded file: tiny.jpg", annotationType: "image")
        context.insert(session)
        context.insert(step)
        context.insert(annotation)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let result = try await service.downloadFile(clientID: annotation.clientID)
        #expect(result.data == Data([0xFF, 0xD8, 0xFF]))
        #expect(result.suggestedFilename == "tiny.jpg")
    }

    @Test("SessionAnnotationSyncService: downloadFile fetches a fresh detail record, then downloads the file's bytes and suggested filename")
    func sessionAnnotationDownloadFileFetchesDetailThenBytes() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/session-annotations/66") {
                let json = Data("""
                {"id": 66, "session": 7, "annotation_text": "Uploaded file: tiny_sketch.json", "annotation_type": "sketch", "order": 0, "scratched": false, "file_url": "https://example.test/api/v1/annotations/300/download/?token=xyz"}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            let headers = ["Content-Disposition": "attachment; filename=\"tiny_sketch.json\""]
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, Data("{}".utf8))
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let annotation = CachedSessionAnnotation(serverID: 66, sessionClientID: session.clientID, annotationText: "Uploaded file: tiny_sketch.json", annotationType: "sketch")
        context.insert(session)
        context.insert(annotation)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let result = try await service.downloadFile(clientID: annotation.clientID)
        #expect(result.data == Data("{}".utf8))
        #expect(result.suggestedFilename == "tiny_sketch.json")
    }

    @Test("StepAnnotationSyncService: refreshTranscription updates the cached record from a fresh GET")
    func stepAnnotationRefreshTranscriptionUpdatesCache() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"id": 55, "session": 7, "step": 10, "annotation": 200, "annotation_text": "note", "annotation_type": "audio", "order": 0, "scratched": false, "transcription": "hello world", "language": "en", "translation": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let step = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        let annotation = CachedStepAnnotation(serverID: 55, sessionClientID: session.clientID, stepClientID: step.clientID, annotationText: "note", annotationType: "audio")
        context.insert(session)
        context.insert(step)
        context.insert(annotation)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let applied = try await service.refreshTranscription(serverID: 55)
        #expect(applied)

        let refetched = try context.fetch(FetchDescriptor<CachedStepAnnotation>()).first
        #expect(refetched?.transcription == "hello world")
        #expect(refetched?.language == "en")
    }

    @Test("StepAnnotationSyncService: refreshTranscription no-ops for an unknown server ID")
    func stepAnnotationRefreshTranscriptionNoOpsForUnknownID() async throws {
        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedStepAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let applied = try await service.refreshTranscription(serverID: 999)
        #expect(!applied)
    }

    @Test("SessionAnnotationSyncService: refreshTranscription updates the cached record from a fresh GET")
    func sessionAnnotationRefreshTranscriptionUpdatesCache() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"id": 66, "session": 7, "annotation_text": "note", "annotation_type": "audio", "order": 0, "scratched": false, "transcription": "hi there", "language": "en", "translation": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedSessionAnnotation.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let annotation = CachedSessionAnnotation(serverID: 66, sessionClientID: session.clientID, annotationText: "note", annotationType: "audio")
        context.insert(session)
        context.insert(annotation)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let applied = try await service.refreshTranscription(serverID: 66)
        #expect(applied)

        let refetched = try context.fetch(FetchDescriptor<CachedSessionAnnotation>()).first
        #expect(refetched?.transcription == "hi there")
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

    @Test("InventorySyncService.searchStoredReagentsWithMolecularWeight hits stored-reagents with search + molecular_weight__isnull=false, and returns [] under the 2-character minimum without a network call")
    func searchStoredReagentsWithMolecularWeightSendsCorrectQuery() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/stored-reagents"))
            let query = request.url!.query ?? ""
            #expect(query.contains("search=NaOH"))
            #expect(query.contains("molecular_weight__isnull=false"))
            #expect(query.contains("limit=10"))
            let json = Data(#"""
            {"count":1,"next":null,"previous":null,"results":[{"id":2,"reagent":1,"reagent_name":"NaOH","reagent_unit":"mL","storage_object":null,"quantity":10.0,"current_quantity":10.0,"barcode":null,"expiration_date":null,"low_stock_threshold":null,"molecular_weight":"40.0000"}]}
            """#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStorageObject.self, CachedReagent.self, CachedStoredReagent.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let results = try await service.searchStoredReagentsWithMolecularWeight(search: "NaOH")
        #expect(results.count == 1)
        #expect(results.first?.reagentName == "NaOH")
        #expect(results.first?.molecularWeight == "40.0000")

        let shortResults = try await service.searchStoredReagentsWithMolecularWeight(search: "N")
        #expect(shortResults.isEmpty)
    }

    @Test("InventorySyncService caches a stored reagent's auto-created metadata_table_id from refetchStoredReagents, then refreshMetadataTable populates its columns")
    func inventorySyncCachesAndRefreshesMetadataTable() async throws {
        StubURLProtocol.handler = { request in
            let path = request.url!.path
            let json: Data
            if path.hasSuffix("stored-reagents") {
                json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":5,"reagent":2,"reagent_name":"NaCl","reagent_unit":"g","storage_object":1,"storage_object_name":"Freezer A","quantity":100.0,"current_quantity":87.5,"barcode":null,"expiration_date":null,"low_stock_threshold":10.0,"metadata_table_id":7,"metadata_table_name":"NaCl (Freezer A) Specifications"}]}"#.utf8)
            } else {
                json = Data("""
                {"id": 7, "name": "NaCl (Freezer A) Specifications", "description": null, "sample_count": 1,
                 "version": "1.0", "owner_username": "testuser", "lab_group_name": null,
                 "is_published": false, "can_edit": true,
                 "columns": [{"id": 3, "name": "Purity", "display_name": "Purity",
                              "type": "characteristics", "column_position": 0, "value": "99.9%",
                              "not_applicable": false, "not_available": false, "mandatory": false, "hidden": false,
                              "readonly": false, "ontology_type": null, "staff_only": false}]}
                """.utf8)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStorageObject.self, CachedReagent.self, CachedStoredReagent.self, CachedMetadataTable.self, CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchStoredReagents()
        let context = ModelContext(container)
        let storedReagent = try context.fetch(FetchDescriptor<CachedStoredReagent>()).first
        #expect(storedReagent?.metadataTableServerID == 7)

        try await service.refreshMetadataTable(metadataTableServerID: 7)
        let columns = try context.fetch(FetchDescriptor<CachedMetadataColumn>())
        #expect(columns.first?.name == "Purity")
        #expect(columns.first?.value == "99.9%")
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

    @Test("InstrumentSyncService caches the instrument's auto-created metadata_table_id from refetchInstruments, then refreshMetadataTable populates its columns")
    func instrumentSyncCachesAndRefreshesMetadataTable() async throws {
        StubURLProtocol.handler = { request in
            let path = request.url!.path
            let json: Data
            if path.hasSuffix("instruments") {
                json = Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":1,"instrument_name":"Mass Spec 1","instrument_description":"Orbitrap","enabled":true,"accepts_bookings":true,"allow_overlapping_bookings":false,"maintenance_overdue":false,"metadata_table_id":42,"metadata_table_name":"Mass Spec 1 Specifications"}]}"#.utf8)
            } else {
                json = Data("""
                {"id": 42, "name": "Mass Spec 1 Specifications", "description": null, "sample_count": 1,
                 "version": "1.0", "owner_username": "testuser", "lab_group_name": null,
                 "is_published": false, "can_edit": true,
                 "columns": [{"id": 9, "name": "Manufacturer", "display_name": "Manufacturer",
                              "type": "characteristics", "column_position": 0, "value": "Thermo",
                              "not_applicable": false, "not_available": false, "mandatory": false, "hidden": false,
                              "readonly": false, "ontology_type": null, "staff_only": false}]}
                """.utf8)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedInstrument.self, CachedMetadataTable.self, CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await service.refetchInstruments()
        let context = ModelContext(container)
        let instrument = try context.fetch(FetchDescriptor<CachedInstrument>()).first
        #expect(instrument?.metadataTableServerID == 42)

        try await service.refreshMetadataTable(instrumentServerID: 1, metadataTableServerID: 42)
        let columns = try context.fetch(FetchDescriptor<CachedMetadataColumn>())
        #expect(columns.first?.name == "Manufacturer")
        #expect(columns.first?.value == "Thermo")
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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

    @Test("OutboxService.replayPending reports push progress with a generic per-operation-type label before replaying each entry")
    func outboxReplayReportsPushProgress() async throws {
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        try context.save()
        let clientID = localProtocol.clientID

        try await outbox.enqueueCreateProtocol(clientID: clientID, title: "Sample Prep", description: nil, enabled: false)

        nonisolated(unsafe) var reportedProgress: [SyncProgress] = []
        await outbox.replayPending(onProgress: { progress in
            reportedProgress.append(progress)
        })

        #expect(reportedProgress.count == 1, "one progress update should be reported for the one queued entry")
        #expect(reportedProgress.first?.direction == .push)
        #expect(reportedProgress.first?.label == "Pushing protocol…")
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSection = CachedProtocolSection(sectionDescription: "Setup", order: 0, protocolModel: localProtocol)
        context.insert(localSection)
        try context.save()

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSection = CachedProtocolSection(sectionDescription: "Setup", order: 0, protocolModel: localProtocol)
        context.insert(localSection)
        try context.save()

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSession = CachedSession(name: "Run 1", enabled: true, isRunning: true, status: "running", protocolClientIDs: [localProtocol.clientID])
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSession = CachedSession(name: "Run 1", enabled: true, isRunning: true, status: "running", protocolClientIDs: [localProtocol.clientID])
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

    @Test("OutboxService retries a session attached to two protocols when only one has synced")
    func outboxReplayRetriesSessionWithPartiallySyncedProtocols() async throws {
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let syncedProtocol = CachedProtocol(serverID: 50, protocolTitle: "Synced", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        let unsyncedProtocol = CachedProtocol(protocolTitle: "Not Synced Yet", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(syncedProtocol)
        context.insert(unsyncedProtocol)
        let localSession = CachedSession(
            name: "Run 1", enabled: true, isRunning: true, status: "running",
            protocolClientIDs: [syncedProtocol.clientID, unsyncedProtocol.clientID]
        )
        context.insert(localSession)
        try context.save()

        try await outbox.enqueueCreateSession(clientID: localSession.clientID)
        await outbox.replayPending()

        let entries = try context.fetch(FetchDescriptor<OutboxEntry>())
        #expect(entries.count == 1, "a session with any unsynced protocol should retry, not be dropped or marked failed")
        #expect(entries.first?.status == OutboxEntryStatus.pending.rawValue)

        let sessions = try context.fetch(FetchDescriptor<CachedSession>())
        #expect(sessions.first?.serverID == nil)
    }

    @Test("syncLocallyCreatedSession succeeds immediately for a protocol-less session")
    func syncLocallyCreatedSessionZeroProtocolsSucceedsImmediately() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect((sentJSON["protocols"] as? [Int64])?.isEmpty == true)
            let json = Data("""
            {"id": 20, "unique_id": "abc", "name": "Notes Only", "enabled": true, "processing": false,
             "started_at": null, "ended_at": null, "is_running": null, "status": "running", "protocols": []}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedSession.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let context = ModelContext(container)
        let localSession = CachedSession(name: "Notes Only", enabled: true, isRunning: true, status: "running", protocolClientIDs: [])
        context.insert(localSession)
        try context.save()

        let serverID = try await service.syncLocallyCreatedSession(clientID: localSession.clientID)
        #expect(serverID == 20)

        let sessions = try context.fetch(FetchDescriptor<CachedSession>())
        #expect(sessions.first?.serverID == 20)
    }

    @Test("syncLocallyCreatedSession posts every attached protocol's serverID once all have synced")
    func syncLocallyCreatedSessionMultiProtocolSucceeds() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let protocols = try #require(sentJSON["protocols"] as? [Int64])
            #expect(Set(protocols) == Set([40, 41]))
            let json = Data("""
            {"id": 21, "unique_id": "abc", "name": "Multi", "enabled": true, "processing": false,
             "started_at": null, "ended_at": null, "is_running": null, "status": "running", "protocols": [40, 41]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedSession.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let context = ModelContext(container)
        let protocolA = CachedProtocol(serverID: 40, protocolTitle: "A", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        let protocolB = CachedProtocol(serverID: 41, protocolTitle: "B", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(protocolA)
        context.insert(protocolB)
        let localSession = CachedSession(
            name: "Multi", enabled: true, isRunning: true, status: "running",
            protocolClientIDs: [protocolA.clientID, protocolB.clientID]
        )
        context.insert(localSession)
        try context.save()

        let serverID = try await service.syncLocallyCreatedSession(clientID: localSession.clientID)
        #expect(serverID == 21)
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localStep = CachedProtocolStep(stepDescription: "Mix", order: 0, stepDuration: nil)
        context.insert(localStep)
        let localReagent = CachedReagent(name: "NaCl", unit: "g")
        context.insert(localReagent)
        let localStepReagent = CachedStepReagent(stepClientID: localStep.clientID, reagentClientID: localReagent.clientID, quantity: 5.0, scalable: false, scalableFactor: 1.0)
        context.insert(localStepReagent)
        try context.save()

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSession = CachedSession(name: "Run 1", enabled: true, isRunning: true, status: "running", protocolClientIDs: [localProtocol.clientID])
        context.insert(localSession)
        let localStep = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(localStep)
        let localAnnotation = CachedStepAnnotation(sessionClientID: localSession.clientID, stepClientID: localStep.clientID, annotationText: "Gloves are on.", annotationType: "text", order: 0)
        context.insert(localAnnotation)
        try context.save()

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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

    @Test("OutboxService replays a queued audio annotation, uploading the persisted local recording and attaching its serverID")
    func outboxReplayResolvesAudioAnnotation() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/upload/step-annotation-chunks") {
                let json = Data("""
                {"annotation_id": 200, "step_annotation_id": 300, "message": "ok"}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            let json = Data("""
            {"id": 300, "session": 9, "step": 10, "annotation": 200,
             "annotation_text": "", "annotation_type": "audio", "order": 0,
             "transcribed": true, "transcription": "Gloves are on.", "language": "en-US", "translation": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localSession = CachedSession(serverID: 9, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(localSession)
        let localStep = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(localStep)
        try context.save()

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data([0x00, 0x01, 0x02]).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let clientID = try await stepAnnotationSync.createAudioAnnotation(
            sessionClientID: localSession.clientID,
            stepClientID: localStep.clientID,
            recordedFileURL: tempFile,
            transcription: "Gloves are on.",
            language: "en-US",
            translation: nil
        )

        try await outbox.enqueueCreateStepAudioAnnotation(clientID: clientID)
        await outbox.replayPending()

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.first?.serverID == 300)
        #expect(annotations.first?.pendingFileName == nil)
        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService replays a queued photo annotation, uploading the persisted local image and attaching its serverID")
    func outboxReplayResolvesImageAnnotation() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"annotation_id": 201, "step_annotation_id": 301, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localSession = CachedSession(serverID: 9, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(localSession)
        let localStep = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(localStep)
        try context.save()

        let clientID = try await stepAnnotationSync.createImageAnnotation(
            sessionClientID: localSession.clientID,
            stepClientID: localStep.clientID,
            imageData: Data([0xFF, 0xD8, 0xFF])
        )

        try await outbox.enqueueCreateStepImageAnnotation(clientID: clientID)
        await outbox.replayPending()

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.first?.serverID == 301)
        #expect(annotations.first?.pendingFileName == nil)
        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService replays a queued video annotation, uploading the persisted local video and attaching its serverID")
    func outboxReplayResolvesVideoAnnotation() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"annotation_id": 202, "step_annotation_id": 302, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localSession = CachedSession(serverID: 9, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(localSession)
        let localStep = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(localStep)
        try context.save()

        let clientID = try await stepAnnotationSync.createVideoAnnotation(
            sessionClientID: localSession.clientID,
            stepClientID: localStep.clientID,
            videoData: Data([0x00, 0x00, 0x00, 0x18]),
            fileExtension: "mov"
        )

        try await outbox.enqueueCreateStepVideoAnnotation(clientID: clientID)
        await outbox.replayPending()

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.first?.serverID == 302)
        #expect(annotations.first?.pendingFileName == nil)
        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
    }

    @Test("OutboxService replays a queued sketch annotation, uploading the persisted local sketch JSON and attaching its serverID")
    func outboxReplayResolvesSketchAnnotation() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"annotation_id": 203, "step_annotation_id": 303, "message": "ok"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
        let localSession = CachedSession(serverID: 9, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(localSession)
        let localStep = CachedProtocolStep(serverID: 10, stepDescription: "Put on gloves", order: 0)
        context.insert(localStep)
        try context.save()

        let clientID = try await stepAnnotationSync.createSketchAnnotation(
            sessionClientID: localSession.clientID,
            stepClientID: localStep.clientID,
            sketchData: Data("{}".utf8)
        )

        try await outbox.enqueueCreateStepSketchAnnotation(clientID: clientID)
        await outbox.replayPending()

        let annotations = try context.fetch(FetchDescriptor<CachedStepAnnotation>())
        #expect(annotations.first?.serverID == 303)
        #expect(annotations.first?.pendingFileName == nil)
        #expect(try context.fetch(FetchDescriptor<OutboxEntry>()).isEmpty)
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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

    @Test("syncLocallyCreatedStoredReagent sends notes/molecularWeight/shareable/accessAll/notifyOnLowStock/pngBase64 and caches them")
    func createStoredReagentSendsNewFieldsAndCachesResult() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["notes"] as? String == "Keep refrigerated")
            #expect(json["molecular_weight"] as? String == "58.4400")
            #expect(json["shareable"] as? Bool == true)
            #expect(json["access_all"] as? Bool == true)
            #expect(json["notify_on_low_stock"] as? Bool == true)
            #expect(json["png_base64"] as? String == "aGVsbG8=")

            let responseJSON = Data("""
            {"id": 31, "reagent": 3, "reagent_name": "NaCl", "reagent_unit": "g",
             "storage_object": 5, "storage_object_name": "Fridge A", "quantity": 100.0,
             "current_quantity": 100.0, "barcode": null, "expiration_date": null, "low_stock_threshold": null,
             "molecular_weight": "58.4400", "notes": "Keep refrigerated", "shareable": true,
             "access_all": true, "notify_on_low_stock": true, "png_base64": "aGVsbG8="}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, responseJSON)
        }

        let container = try makeInMemoryContainer(for: [CachedStorageObject.self, CachedReagent.self, CachedStoredReagent.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let context = ModelContext(container)
        let localStoredReagent = CachedStoredReagent(
            reagentServerID: 3, reagentName: "NaCl", reagentUnit: "g",
            storageObjectServerID: 5, storageObjectName: "Fridge A",
            quantity: 100.0, currentQuantity: 100.0,
            molecularWeight: 58.44, notes: "Keep refrigerated",
            shareable: true, accessAll: true, notifyOnLowStock: true,
            pngBase64: "aGVsbG8="
        )
        context.insert(localStoredReagent)
        try context.save()

        try await inventorySync.syncLocallyCreatedStoredReagent(clientID: localStoredReagent.clientID)

        let storedReagents = try context.fetch(FetchDescriptor<CachedStoredReagent>())
        #expect(storedReagents.first?.molecularWeight == 58.44)
        #expect(storedReagents.first?.notes == "Keep refrigerated")
        #expect(storedReagents.first?.shareable == true)
        #expect(storedReagents.first?.accessAll == true)
        #expect(storedReagents.first?.notifyOnLowStock == true)
        #expect(storedReagents.first?.pngBase64 == "aGVsbG8=")
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

        let context = ModelContext(container)
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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)

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

    @Test("ProjectSyncService.update PATCHes the project and updates the cache")
    func projectUpdatePatches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/projects/9"))
            let json = Data(#"{"id": 9, "project_name": "Renamed", "project_description": "New description"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProject.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await projectSync.update(serverID: 9, projectName: "Renamed", projectDescription: "New description")
        #expect(dto.projectName == "Renamed")

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedProject>(predicate: #Predicate { $0.serverID == 9 })).first
        #expect(cached?.projectName == "Renamed")
    }

    @Test("ProjectSyncService.delete DELETEs the project and removes it from the cache")
    func projectDeleteRemovesLocal() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/projects/9"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedProject.self])
        let context = ModelContext(container)
        context.insert(CachedProject(serverID: 9, projectName: "To Delete", projectDescription: nil))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await projectSync.delete(serverID: 9)

        let remaining = try context.fetch(FetchDescriptor<CachedProject>())
        #expect(remaining.isEmpty)
    }

    @Test("ProtocolSyncService.update PATCHes the protocol and updates the cache")
    func protocolUpdatePatches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/protocols/12"))
            let json = Data(#"{"id": 12, "protocol_title": "Renamed", "protocol_description": "New desc", "enabled": true}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await protocolSync.update(serverID: 12, protocolTitle: "Renamed", protocolDescription: "New desc", enabled: true)
        #expect(dto.protocolTitle == "Renamed")

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.serverID == 12 })).first
        #expect(cached?.protocolTitle == "Renamed")
        #expect(cached?.enabled == true)
    }

    @Test("ProtocolSyncService.delete DELETEs the protocol and removes it from the cache")
    func protocolDeleteRemovesLocal() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/protocols/12"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let context = ModelContext(container)
        context.insert(CachedProtocol(serverID: 12, protocolTitle: "To Delete", protocolDescription: nil, enabled: false, isLocallyAuthored: true))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await protocolSync.delete(serverID: 12)

        let remaining = try context.fetch(FetchDescriptor<CachedProtocol>())
        #expect(remaining.isEmpty)
    }

    @Test("InventorySyncService.createStorageObject POSTs the right body and caches the result")
    func storageObjectCreateCachesResult() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["object_name"] as? String == "Test Freezer")
            #expect(sentJSON["object_type"] as? String == "freezer")
            let json = Data(#"{"id": 5, "object_type": "freezer", "object_name": "Test Freezer", "object_description": null, "stored_at": null}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStorageObject.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await inventorySync.createStorageObject(objectName: "Test Freezer", objectType: "freezer", objectDescription: nil, storedAt: nil)
        #expect(dto.id == 5)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedStorageObject>(predicate: #Predicate { $0.serverID == 5 })).first
        #expect(cached?.objectName == "Test Freezer")
    }

    @Test("InventorySyncService.deleteStorageObject DELETEs and removes it from the cache")
    func storageObjectDeleteRemovesLocal() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/storage-objects/5"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedStorageObject.self])
        let context = ModelContext(container)
        context.insert(CachedStorageObject(serverID: 5, objectType: "freezer", objectName: "To Delete"))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await inventorySync.deleteStorageObject(serverID: 5)

        let remaining = try context.fetch(FetchDescriptor<CachedStorageObject>())
        #expect(remaining.isEmpty)
    }

    @Test("InstrumentSyncService.createInstrument POSTs the right body and caches the result")
    func instrumentCreateCachesResult() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["instrument_name"] as? String == "Test Centrifuge")
            let json = Data(#"{"id": 9, "instrument_name": "Test Centrifuge", "instrument_description": null, "enabled": true, "accepts_bookings": true, "allow_overlapping_bookings": false, "maintenance_overdue": false}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedInstrument.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await instrumentSync.createInstrument(instrumentName: "Test Centrifuge", instrumentDescription: nil, enabled: true, acceptsBookings: true, allowOverlappingBookings: false)
        #expect(dto.id == 9)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedInstrument>(predicate: #Predicate { $0.serverID == 9 })).first
        #expect(cached?.instrumentName == "Test Centrifuge")
    }

    @Test("InstrumentSyncService.updateInstrument PATCHes the right path and updates the cache")
    func instrumentUpdatePatches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/instruments/9"))
            let json = Data(#"{"id": 9, "instrument_name": "Renamed Centrifuge", "instrument_description": null, "enabled": false, "accepts_bookings": true, "allow_overlapping_bookings": false, "maintenance_overdue": false}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedInstrument.self])
        let context = ModelContext(container)
        context.insert(CachedInstrument(serverID: 9, instrumentName: "Test Centrifuge", enabled: true, acceptsBookings: true, allowOverlappingBookings: false, maintenanceOverdue: false))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await instrumentSync.updateInstrument(serverID: 9, instrumentName: "Renamed Centrifuge", instrumentDescription: nil, enabled: false, acceptsBookings: true, allowOverlappingBookings: false)

        let cached = try context.fetch(FetchDescriptor<CachedInstrument>(predicate: #Predicate { $0.serverID == 9 })).first
        #expect(cached?.instrumentName == "Renamed Centrifuge")
        #expect(cached?.enabled == false)
    }

    @Test("InstrumentSyncService.deleteInstrument DELETEs and removes it from the cache")
    func instrumentDeleteRemovesLocal() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/instruments/9"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedInstrument.self])
        let context = ModelContext(container)
        context.insert(CachedInstrument(serverID: 9, instrumentName: "To Delete", enabled: true, acceptsBookings: true, allowOverlappingBookings: false, maintenanceOverdue: false))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await instrumentSync.deleteInstrument(serverID: 9)

        let remaining = try context.fetch(FetchDescriptor<CachedInstrument>())
        #expect(remaining.isEmpty)
    }

    @Test("ProtocolSyncService.updateSection PATCHes the section and updates the cache")
    func sectionUpdatePatches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/sections/14"))
            let json = Data(#"{"id": 14, "section_description": "Renamed", "order": 0, "section_duration": 300, "steps": []}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let context = ModelContext(container)
        context.insert(CachedProtocolSection(serverID: 14, sectionDescription: "Old", order: 0))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await protocolSync.updateSection(serverID: 14, sectionDescription: "Renamed", sectionDuration: 300)

        let cached = try context.fetch(FetchDescriptor<CachedProtocolSection>(predicate: #Predicate { $0.serverID == 14 })).first
        #expect(cached?.sectionDescription == "Renamed")
        #expect(cached?.sectionDuration == 300)
    }

    @Test("ProtocolSyncService.deleteSection DELETEs the section and removes it from the cache")
    func sectionDeleteRemovesLocal() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/sections/14"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let context = ModelContext(container)
        context.insert(CachedProtocolSection(serverID: 14, sectionDescription: "To Delete", order: 0))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await protocolSync.deleteSection(serverID: 14)

        let remaining = try context.fetch(FetchDescriptor<CachedProtocolSection>())
        #expect(remaining.isEmpty)
    }

    @Test("ProtocolSyncService.updateStep PATCHes the step and updates the cache")
    func stepUpdatePatches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/steps/22"))
            let json = Data(#"{"id": 22, "step_description": "Renamed step", "order": 0, "step_duration": 60}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let context = ModelContext(container)
        context.insert(CachedProtocolStep(serverID: 22, stepDescription: "Old step", order: 0))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await protocolSync.updateStep(serverID: 22, stepDescription: "Renamed step", stepDuration: 60)

        let cached = try context.fetch(FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.serverID == 22 })).first
        #expect(cached?.stepDescription == "Renamed step")
        #expect(cached?.stepDuration == 60)
    }

    @Test("ProtocolSyncService.deleteStep DELETEs the step and removes it from the cache")
    func stepDeleteRemovesLocal() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/steps/22"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let context = ModelContext(container)
        context.insert(CachedProtocolStep(serverID: 22, stepDescription: "To Delete", order: 0))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await protocolSync.deleteStep(serverID: 22)

        let remaining = try context.fetch(FetchDescriptor<CachedProtocolStep>())
        #expect(remaining.isEmpty)
    }

    @Test("StepReagentSyncService.update PATCHes the step-reagent and updates the cache")
    func stepReagentUpdatePatches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/step-reagents/3"))
            let json = Data(#"{"id": 3, "step": 22, "reagent": {"id": 1, "name": "NaOH", "unit": "mL"}, "quantity": 10, "scalable": false, "scalable_factor": 1}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStepReagent.self, CachedReagent.self])
        let context = ModelContext(container)
        context.insert(CachedStepReagent(serverID: 3, stepClientID: UUID(), reagentClientID: UUID(), quantity: 5, scalable: false, scalableFactor: 1))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await stepReagentSync.update(serverID: 3, quantity: 10, scalable: false, scalableFactor: 1)

        let cached = try context.fetch(FetchDescriptor<CachedStepReagent>(predicate: #Predicate { $0.serverID == 3 })).first
        #expect(cached?.quantity == 10)
    }

    @Test("StepReagentSyncService.delete DELETEs the step-reagent and removes it from the cache")
    func stepReagentDeleteRemovesLocal() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/step-reagents/3"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedStepReagent.self, CachedReagent.self])
        let context = ModelContext(container)
        context.insert(CachedStepReagent(serverID: 3, stepClientID: UUID(), reagentClientID: UUID(), quantity: 5, scalable: false, scalableFactor: 1))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await stepReagentSync.delete(serverID: 3)

        let remaining = try context.fetch(FetchDescriptor<CachedStepReagent>())
        #expect(remaining.isEmpty)
    }

    @Test("SessionSyncService.update PATCHes the session and updates the cache")
    func sessionUpdatePatches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/sessions/6"))
            let json = Data(#"{"id": 6, "unique_id": "abc", "name": "Renamed", "enabled": true, "protocols": []}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocol.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await sessionSync.update(serverID: 6, name: "Renamed", enabled: true)
        #expect(dto.name == "Renamed")

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == 6 })).first
        #expect(cached?.name == "Renamed")
        #expect(cached?.enabled == true)
    }

    @Test("SessionSyncService.delete DELETEs the session and removes it from the cache")
    func sessionDeleteRemovesLocal() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/sessions/6"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocol.self])
        let context = ModelContext(container)
        context.insert(CachedSession(serverID: 6, name: "To Delete", enabled: false, isRunning: nil, status: "draft"))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await sessionSync.delete(serverID: 6)

        let remaining = try context.fetch(FetchDescriptor<CachedSession>())
        #expect(remaining.isEmpty)
    }

    @Test("LabGroupSyncService.setPermission POSTs a new grant when none exists yet")
    func setPermissionCreatesWhenNoneExists() async throws {
        StubURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                let json = Data(#"{"count": 0, "next": null, "previous": null, "results": []}"#.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(request.httpMethod == "POST")
            let json = Data(#"{"id": 5, "user": 2, "user_username": "alice", "lab_group": 1, "can_view": true, "can_invite": false, "can_manage": false, "can_process_jobs": true}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedLabGroup.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let labGroupSync = LabGroupSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await labGroupSync.setPermission(userServerID: 2, labGroupServerID: 1, canView: true, canInvite: false, canManage: false, canProcessJobs: true)
        #expect(dto.id == 5)
        #expect(dto.canProcessJobs)
    }

    @Test("LabGroupSyncService.setPermission PATCHes an existing grant rather than risking a duplicate POST")
    func setPermissionPatchesWhenAlreadyExists() async throws {
        nonisolated(unsafe) var sawPost = false
        StubURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                let json = Data(#"{"count": 1, "next": null, "previous": null, "results": [{"id": 5, "user": 2, "user_username": "alice", "lab_group": 1, "can_view": true, "can_invite": false, "can_manage": false, "can_process_jobs": false}]}"#.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            if request.httpMethod == "POST" { sawPost = true }
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/lab-group-permissions/5"))
            let json = Data(#"{"id": 5, "user": 2, "user_username": "alice", "lab_group": 1, "can_view": true, "can_invite": true, "can_manage": false, "can_process_jobs": true}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedLabGroup.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let labGroupSync = LabGroupSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await labGroupSync.setPermission(userServerID: 2, labGroupServerID: 1, canView: true, canInvite: true, canManage: false, canProcessJobs: true)
        #expect(dto.canInvite)
        #expect(!sawPost, "must never POST a duplicate permission grant once one is known to exist")
    }

    private static let sampleLabGroupJSON = #"""
        {
            "id": 71, "name": "Research Group", "description": null, "parent_group": null,
            "full_path": [{"id": 71, "name": "Research Group"}],
            "creator": 1, "creator_name": "testuser", "is_active": true,
            "allow_member_invites": true, "allow_process_jobs": false,
            "member_count": 1, "sub_groups_count": 0,
            "is_creator": true, "is_member": true, "can_invite": true, "can_manage": true, "can_process_jobs": true,
            "created_at": "2026-07-25T14:00:00Z", "updated_at": "2026-07-25T14:00:00Z"
        }
        """#

    @Test("LabGroupSyncService.create POSTs the new group and caches the result")
    func createLabGroupPostsAndCaches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/lab-groups"))
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(Self.sampleLabGroupJSON.utf8))
        }

        let container = try makeInMemoryContainer(for: [CachedLabGroup.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let labGroupSync = LabGroupSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await labGroupSync.create(name: "Research Group", description: nil, parentGroupServerID: nil, allowMemberInvites: true, allowProcessJobs: false)
        #expect(dto.id == 71)
        #expect(dto.fullPath.first?.name == "Research Group")

        let context = ModelContext(container)
        let cached = try context.fetch(FetchDescriptor<CachedLabGroup>())
        #expect(cached.count == 1)
        #expect(cached.first?.isCreator == true)
        #expect(cached.first?.canManage == true)
    }

    @Test("LabGroupSyncService.update PATCHes the group and refreshes the cache")
    func updateLabGroupPatchesAndCaches() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/lab-groups/71"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.sampleLabGroupJSON.utf8))
        }

        let container = try makeInMemoryContainer(for: [CachedLabGroup.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let labGroupSync = LabGroupSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await labGroupSync.update(labGroupServerID: 71, request: UpdateLabGroupRequest(name: "Research Group"))
        #expect(dto.name == "Research Group")
    }

    @Test("LabGroupSyncService.deleteGroup DELETEs and removes the cached row")
    func deleteLabGroupRemovesCachedRow() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedLabGroup.self])
        let context = ModelContext(container)
        context.insert(CachedLabGroup(serverID: 71, name: "Research Group"))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let labGroupSync = LabGroupSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        try await labGroupSync.deleteGroup(labGroupServerID: 71)

        let remaining = try context.fetch(FetchDescriptor<CachedLabGroup>())
        #expect(remaining.isEmpty)
    }

    @Test("LabGroupSyncService.inviteUser POSTs the invite and returns the real response shape")
    func inviteUserPostsRequest() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/lab-groups/71/invite_user"))
            let json = Data(#"""
                {
                "id": 1, "lab_group": 71, "lab_group_name": "Research Group", "inviter": 1, "inviter_name": "testuser",
                "invited_user": null, "invited_email": "invitee@example.com", "status": "pending", "message": "join please",
                "expires_at": "2026-08-01T00:00:00Z", "responded_at": null, "can_accept": true,
                "created_at": "2026-07-25T14:00:00Z", "updated_at": "2026-07-25T14:00:00Z"
                }
                """#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedLabGroup.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let labGroupSync = LabGroupSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await labGroupSync.inviteUser(labGroupServerID: 71, email: "invitee@example.com", message: "join please")
        #expect(dto.invitedEmail == "invitee@example.com")
        #expect(dto.status == "pending")
    }

    @Test("LabGroupSyncService.fetchMyPendingInvitations decodes the real plain-array (non-paginated) response shape")
    func fetchMyPendingInvitationsDecodesPlainArray() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/lab-group-invitations/my_pending_invitations"))
            let json = Data(#"""
                [{
                "id": 2, "lab_group": 71, "lab_group_name": "Research Group", "inviter": 1, "inviter_name": "testuser",
                "invited_user": null, "invited_email": "me@example.com", "status": "pending", "message": null,
                "expires_at": null, "responded_at": null, "can_accept": true,
                "created_at": "2026-07-25T14:00:00Z", "updated_at": "2026-07-25T14:00:00Z"
                }]
                """#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedLabGroup.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let labGroupSync = LabGroupSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let invitations = try await labGroupSync.fetchMyPendingInvitations()
        #expect(invitations.count == 1)
        #expect(invitations.first?.invitedEmail == "me@example.com")
    }

    private static let sampleUserProfileJSON = #"""
        {
            "id": 1, "username": "testuser", "email": "testuser@example.com",
            "first_name": "Test", "last_name": "User", "is_staff": true, "is_superuser": false,
            "is_active": true, "date_joined": "2026-07-05T21:43:37Z", "last_login": "2026-07-25T17:06:34Z",
            "has_orcid": false, "orcid_id": null, "orcid_name": null
        }
        """#

    @Test("UserProfileSyncService.fetchProfile GETs the real users/{id}/ endpoint")
    func fetchProfileGetsRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url!.path.hasSuffix("/users/1"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(Self.sampleUserProfileJSON.utf8))
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let userProfileSync = UserProfileSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let profile = try await userProfileSync.fetchProfile(userID: 1)
        #expect(profile.username == "testuser")
        #expect(profile.firstName == "Test")
        #expect(profile.isStaff)
    }

    @Test("UserProfileSyncService.updateProfile POSTs the real update_profile endpoint and returns the nested user")
    func updateProfilePostsRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/users/update_profile"))
            let json = Data(#"""
                {"message": "Profile updated successfully", "user": \#(Self.sampleUserProfileJSON)}
                """#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let userProfileSync = UserProfileSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let profile = try await userProfileSync.updateProfile(firstName: "Test", lastName: "User", email: nil, currentPassword: nil)
        #expect(profile.email == "testuser@example.com")
    }

    @Test("UserProfileSyncService.changePassword POSTs the real change_password endpoint")
    func changePasswordPostsRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/users/change_password"))
            let json = Data(#"{"message": "Password changed successfully"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let userProfileSync = UserProfileSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        try await userProfileSync.changePassword(currentPassword: "old", newPassword: "new12345", confirmPassword: "new12345")
    }

    private static let sampleDeviceTokenJSON = #"""
        {
            "id": 967, "token": "abc123", "label": "Test Device", "description": "",
            "permission": "write", "enabled": true, "user": 1, "username": "testuser",
            "created_at": "2026-07-25T18:32:38Z", "last_used_at": null, "expires_at": null, "is_expired": false
        }
        """#

    @Test("DeviceTokenSyncService.fetchPage GETs the real paginated device-tokens endpoint")
    func fetchPageGetsRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url!.path.hasSuffix("/device-tokens"))
            let json = Data(#"""
                {"count": 1, "next": null, "previous": null, "results": [\#(Self.sampleDeviceTokenJSON)]}
                """#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let deviceTokenSync = DeviceTokenSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let page = try await deviceTokenSync.fetchPage(offset: 0, limit: 25)
        #expect(page.count == 1)
        #expect(page.results.first?.label == "Test Device")
        #expect(page.results.first?.token == "abc123")
    }

    @Test("DeviceTokenSyncService.rotate POSTs the real rotate endpoint and returns the new token")
    func rotatePostsRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/device-tokens/967/rotate"))
            let json = Data(#"{"token": "newtoken456"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let deviceTokenSync = DeviceTokenSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let newToken = try await deviceTokenSync.rotate(id: 967)
        #expect(newToken == "newtoken456")
    }

    @Test("DeviceTokenSyncService.toggle POSTs the real toggle endpoint and returns the new enabled state")
    func togglePostsRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/device-tokens/967/toggle"))
            let json = Data(#"{"enabled": false}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let deviceTokenSync = DeviceTokenSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let enabled = try await deviceTokenSync.toggle(id: 967)
        #expect(enabled == false)
    }

    @Test("DeviceTokenSyncService.delete DELETEs the real device-tokens endpoint")
    func deleteDeletesRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/device-tokens/967"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let deviceTokenSync = DeviceTokenSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        try await deviceTokenSync.delete(id: 967)
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

    @Test("InstrumentJobSyncService.updateFunderCostCenter PATCHes both fields and updates the cache")
    func updateFunderCostCenterPatchesJob() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/instrument-jobs/88"))
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["funder"] as? String == "NIH Grant 12345")
            #expect(sentJSON["cost_center"] as? String == "CC-9001")
            let json = Data("""
            {"id": 88, "job_name": "Run 2", "job_type": "analysis", "status": "draft",
             "project": null, "instrument": null, "submitted_at": null, "completed_at": null,
             "lab_group": null, "staff": [], "staff_usernames": [],
             "funder": "NIH Grant 12345", "cost_center": "CC-9001"}
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

        let dto = try await instrumentJobSync.updateFunderCostCenter(jobServerID: 88, funder: "NIH Grant 12345", costCenter: "CC-9001")
        #expect(dto.funder == "NIH Grant 12345")

        let jobs = try context.fetch(FetchDescriptor<CachedInstrumentJob>())
        #expect(jobs.first?.funder == "NIH Grant 12345")
        #expect(jobs.first?.costCenter == "CC-9001")
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

    @Test("MetadataColumnSyncService.fetchOntologySuggestions decodes a Unimod suggestion's full_data, including specifications")
    func fetchOntologySuggestionsDecodesUnimodFullData() async throws {
        StubURLProtocol.handler = { request in
            let json = Data("""
            {"ontology_type": "unimod", "suggestions": [
                {"id": "UNIMOD:35", "value": "UNIMOD:35", "display_name": "Oxidation",
                 "description": "Oxidation or hydroxylation", "ontology_type": "unimod",
                 "full_data": {
                     "accession": "UNIMOD:35", "name": "Oxidation", "definition": "Oxidation or hydroxylation",
                     "delta_mono_mass": "15.994915", "delta_composition": "O",
                     "specifications": {
                         "1": {"site": "M", "position": "Anywhere", "classification": "Post-translational", "hidden": "0"},
                         "2": {"site": "C", "position": "Anywhere", "classification": "Artefact", "hidden": "1"}
                     }
                 }}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let suggestions = try await metadataColumnSync.fetchOntologySuggestions(
            ontologyType: "unimod",
            customFilters: nil,
            search: "oxidation"
        )
        let fullData = try #require(suggestions.first?.fullData)
        #expect(fullData.accession == "UNIMOD:35")
        #expect(fullData.deltaMonoMass == "15.994915")
        #expect(fullData.deltaComposition == "O")
        #expect(fullData.specifications["1"]?["site"] == "M")
        #expect(fullData.specifications["2"]?["hidden"] == "1")
    }

    @Test("OnlineOntologySearchService.search issues one request per enabled type and buckets results per database")
    func onlineOntologySearchBucketsPerType() async throws {
        StubURLProtocol.handler = { request in
            let query = request.url!.query ?? ""
            #expect(query.contains("q=test"))
            if query.contains("type=species") {
                let json = Data("""
                {"ontology_type": "species", "suggestions": [
                    {"id": "9606", "value": "HUMAN", "display_name": "Homo sapiens", "description": "Human", "ontology_type": "species"}
                ]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            } else if query.contains("type=unimod") {
                let json = Data("""
                {"ontology_type": "unimod", "suggestions": [
                    {"id": "UNIMOD:21", "value": "UNIMOD:21", "display_name": "Phospho", "description": "Phosphorylation", "ontology_type": "unimod",
                     "full_data": {"accession": "UNIMOD:21", "name": "Phospho", "definition": "Phosphorylation",
                         "delta_mono_mass": "79.966331", "delta_composition": "H O(3) P", "specifications": {}}}
                ]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            let empty = Data("""
            {"ontology_type": "", "suggestions": []}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, empty)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let ontologySearchSync = OnlineOntologySearchService(metadataColumnSync: metadataColumnSync)

        let buckets = await ontologySearchSync.search(text: "test", enabledTypeKeys: ["species", "unimod"])

        #expect(buckets["species"]?.count == 1)
        #expect(buckets["unimod"]?.count == 1)
        if case .taxonomy(let term) = buckets["species"]?.first {
            #expect(term.scientificName == "Homo sapiens")
        } else {
            Issue.record("expected .taxonomy for species")
        }
        if case .unimod(let term) = buckets["unimod"]?.first {
            #expect(term.deltaMonoMass == "79.966331")
        } else {
            Issue.record("expected .unimod for unimod")
        }
    }

    @Test("OnlineOntologySearchService.search returns no results for a query under 2 characters, without any network call")
    func onlineOntologySearchSkipsShortQuery() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("should not make a network call for a search under 2 characters")
            throw URLError(.badServerResponse)
        }
        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let ontologySearchSync = OnlineOntologySearchService(metadataColumnSync: metadataColumnSync)

        let buckets = await ontologySearchSync.search(text: "h", enabledTypeKeys: ["species"])
        #expect(buckets.isEmpty)
    }

    @Test("OnlineOntologySearchService.search passes the chosen matchType through as the raw match= query param")
    func onlineOntologySearchPassesMatchType() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.query?.contains("match=startswith") == true)
            let empty = Data("""
            {"ontology_type": "", "suggestions": []}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, empty)
        }
        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let ontologySearchSync = OnlineOntologySearchService(metadataColumnSync: metadataColumnSync)

        _ = await ontologySearchSync.search(text: "test", enabledTypeKeys: ["species"], matchType: .startsWith)
    }

    @Test("OnlineOntologySearchService.search decodes ncbi_taxonomy/chebi/subcellular_location full_data into their own rich fields, not just the generic display fields")
    func onlineOntologySearchDecodesTypeSpecificFullData() async throws {
        StubURLProtocol.handler = { request in
            let query = request.url!.query ?? ""
            if query.contains("type=ncbi_taxonomy") {
                let json = Data("""
                {"ontology_type": "ncbi_taxonomy", "suggestions": [
                    {"id": "9606", "value": "Homo sapiens", "display_name": "Homo sapiens", "description": "Human", "ontology_type": "ncbi_taxonomy",
                     "full_data": {"tax_id": 9606, "scientific_name": "Homo sapiens", "common_name": "Human", "synonyms": "Human;", "rank": "species"}}
                ]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            } else if query.contains("type=chebi") {
                let json = Data("""
                {"ontology_type": "chebi", "suggestions": [
                    {"id": "CHEBI:15377", "value": "CHEBI:15377", "display_name": "water", "description": "An oxide of hydrogen.", "ontology_type": "chebi",
                     "full_data": {"identifier": "CHEBI:15377", "name": "water", "definition": "An oxide of hydrogen.",
                         "synonyms": "H2O;", "formula": "H2O", "mass": 18.015, "charge": 0,
                         "inchi": "InChI=1S/H2O/h1H2", "smiles": "[H]O[H]", "parent_terms": null, "roles": null}}
                ]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            } else if query.contains("type=subcellular_location") {
                let json = Data("""
                {"ontology_type": "subcellular_location", "suggestions": [
                    {"id": "SL-0007", "value": "Acrosome", "display_name": "Acrosome", "description": "Spermatid organelle.", "ontology_type": "subcellular_location",
                     "full_data": {"location_identifier": "Acrosome", "topology_identifier": null, "orientation_identifier": null,
                         "accession": "SL-0007", "definition": "Spermatid organelle.", "synonyms": "Acrosomal vesicle.;"}}
                ]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            let empty = Data(#"{"ontology_type": "", "suggestions": []}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, empty)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let ontologySearchSync = OnlineOntologySearchService(metadataColumnSync: metadataColumnSync)

        let buckets = await ontologySearchSync.search(text: "test", enabledTypeKeys: ["ncbi_taxonomy", "chebi", "subcellular_location"])

        if case .taxonomy(let term) = buckets["ncbi_taxonomy"]?.first {
            #expect(term.rank == "species")
            #expect(term.synonyms == "Human;")
        } else {
            Issue.record("expected .taxonomy with rank/synonyms populated from full_data")
        }
        if case .chemicalCompound(let term) = buckets["chebi"]?.first {
            #expect(term.formula == "H2O")
            #expect(term.mass == "18.015")
            #expect(term.charge == 0)
            #expect(term.smiles == "[H]O[H]")
        } else {
            Issue.record("expected .chemicalCompound with formula/mass/charge/smiles populated from full_data")
        }
        if case .subcellularLocation(let term) = buckets["subcellular_location"]?.first {
            #expect(term.title == "Acrosome")
            #expect(term.synonyms == "Acrosomal vesicle.;")
        } else {
            Issue.record("expected .subcellularLocation with synonyms populated from full_data")
        }
    }

    @Test("AsyncTaskSyncService.importSDRFFile(fileData:) posts the given bytes directly, without touching the filesystem")
    func asyncTaskImportSDRFFileDataVariantPostsGivenBytes() async throws {
        StubURLProtocol.handler = { request in
            let body = request.httpBodyStream?.readAllData() ?? request.httpBody ?? Data()
            let bodyString = String(data: body, encoding: .utf8) ?? ""
            #expect(bodyString.contains("name=\"file\"; filename=\"retry.sdrf.tsv\""))
            #expect(bodyString.contains("source name"))
            let json = Data(#"{"task_id": "aaaa1111-c988-465d-ac16-e5c86d3fdc26", "message": "queued"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let fileData = Data("source name\tcharacteristics[organism]\nHCC-001\thomo sapiens\n".utf8)
        let taskID = try await service.importSDRFFile(
            metadataTableServerID: 290, fileData: fileData, fileName: "retry.sdrf.tsv", replaceExisting: true
        )
        #expect(taskID == "aaaa1111-c988-465d-ac16-e5c86d3fdc26")
    }

    @Test("AsyncTaskRetryAction.resubmit re-issues the original export request for a failed task")
    func asyncTaskRetryActionResubmitsExport() async throws {
        nonisolated(unsafe) var hitColumnIDs: [Int64]?
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/async-export/sdrf_file"))
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            hitColumnIDs = (sentJSON["metadata_column_ids"] as? [Int]).map { $0.map(Int64.init) }
            let json = Data(#"{"task_id": "retry-task-id", "message": "queued"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let action = AsyncTaskRetryAction.exportSDRF(metadataTableServerID: 290, metadataColumnIDs: [1, 2, 3], sampleNumber: 5, includePools: true)
        let newTaskID = try await action.resubmit(using: service)
        #expect(newTaskID == "retry-task-id")
        #expect(hitColumnIDs == [1, 2, 3])
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

    @Test("MetadataColumnSyncService.replaceValue POSTs old/new value and update_pools to replace_value")
    func replaceValuePostsCorrectRequest() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/metadata-columns/6957/replace_value"))
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["old_value"] as? String == "human")
            #expect(sentJSON["new_value"] as? String == "rat")
            #expect(sentJSON["update_pools"] as? Bool == true)
            let json = Data("""
            {"message": "Value replacement completed", "old_value": "human", "new_value": "rat",
             "default_value_updated": true, "modifiers_merged": 0, "modifiers_deleted": 0,
             "samples_reverted_to_default": 0, "pool_columns_updated": 2}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataColumn.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let metadataColumnSync = MetadataColumnSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let response = try await metadataColumnSync.replaceValue(columnServerID: 6957, oldValue: "human", newValue: "rat")
        #expect(response.defaultValueUpdated)
        #expect(response.poolColumnsUpdated == 2)
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
             "visibility": "private", "is_default": false, "column_count": 0, "lab_group": null,
             "can_edit": true, "can_delete": true, "schema_names": []}
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
             "visibility": "private", "is_default": false, "column_count": 9, "lab_group": null,
             "can_edit": true, "can_delete": true, "schema_names": ["minimum"]}
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

    @Test("MetadataTableTemplateSyncService.update PATCHes the template and reports schema origin")
    func updateTableTemplateHitsCorrectPath() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/metadata-table-templates/12"))
            let json = Data("""
            {"id": 12, "name": "Renamed", "description": null, "owner_username": "testuser",
             "visibility": "private", "is_default": false, "column_count": 9, "lab_group": null,
             "can_edit": true, "can_delete": true, "schema_names": ["minimum"]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataTableTemplate.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataTableTemplateSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let template = try await templateSync.update(templateServerID: 12, request: CreateMetadataTableTemplateRequest(name: "Renamed"))
        #expect(template.name == "Renamed")
        #expect(template.schemaNames == ["minimum"])
    }

    @Test("MetadataTableTemplateSyncService.delete hits DELETE and removes the cached row")
    func deleteTableTemplateHitsCorrectPathAndClearsCache() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/metadata-table-templates/13"))
            return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
        }

        let container = try makeInMemoryContainer(for: [CachedMetadataTableTemplate.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataTableTemplateSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let context = ModelContext(container)
        context.insert(CachedMetadataTableTemplate(serverID: 13, name: "To Delete"))
        try context.save()

        try await templateSync.delete(templateServerID: 13)

        let remaining = try context.fetch(FetchDescriptor<CachedMetadataTableTemplate>())
        #expect(remaining.isEmpty)
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

    @Test("MetadataColumnTemplateSyncService.shareTemplate POSTs user_id and permission_level to share_template")
    func shareTemplatePostsCorrectRequest() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/column-templates/401/share_template"))
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["user_id"] as? Int == 6)
            #expect(sentJSON["permission_level"] as? String == "edit")
            let json = Data("""
            {"message": "Template share created successfully", "share_id": 1, "user": "importtestuser", "permission_level": "edit"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataColumnTemplateSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let response = try await templateSync.shareTemplate(templateServerID: 401, userID: 6, permissionLevel: "edit")
        #expect(response.shareId == 1)
        #expect(response.user == "importtestuser")
    }

    @Test("MetadataColumnTemplateSyncService.unshareTemplate DELETEs with user_id to unshare_template")
    func unshareTemplateSendsCorrectRequest() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/column-templates/401/unshare_template"))
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["user_id"] as? Int == 6)
            let json = Data("""
            {"message": "Template sharing removed successfully"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataColumnTemplateSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        try await templateSync.unshareTemplate(templateServerID: 401, userID: 6)
    }

    @Test("MetadataColumnTemplateSyncService.fetchShares GETs template-shares filtered by template_id")
    func fetchSharesFiltersByTemplateID() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/template-shares"))
            #expect(request.url!.query?.contains("template_id=401") == true)
            let json = Data("""
            {"count": 1, "next": null, "previous": null, "results": [
                {"id": 1, "template": 401, "user": 6, "user_username": "importtestuser",
                 "shared_by": 1, "shared_by_username": "testuser", "permission_level": "use", "shared_at": "2026-07-28T14:17:21Z"}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let templateSync = MetadataColumnTemplateSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let shares = try await templateSync.fetchShares(templateServerID: 401)
        #expect(shares.count == 1)
        #expect(shares.first?.userUsername == "importtestuser")
        #expect(shares.first?.permissionLevel == "use")
    }

    @Test("AnnotationFolderSyncService.fetchRootFolders resolves each session-attached folder's own details")
    func fetchRootFoldersResolvesFolderDetails() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/session-annotation-folders") {
                #expect(request.url!.query?.contains("session=1") == true)
                let json = Data("""
                {"count": 1, "next": null, "previous": null, "results": [{"id": 1, "session": 1, "folder": 4}]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(request.url!.path.hasSuffix("/annotation-folders/4"))
            let json = Data("""
            {"id": 4, "folder_name": "Root Folder", "parent_folder": null, "full_path": "Root Folder",
             "child_folders_count": 1, "annotations_count": 0, "can_edit": true, "can_delete": true}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedAnnotationFolder.self, CachedFolderAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let folderSync = AnnotationFolderSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let folders = try await folderSync.fetchRootFolders(sessionServerID: 1)
        #expect(folders.count == 1)
        #expect(folders.first?.folderName == "Root Folder")
    }

    @Test("AnnotationFolderSyncService.fetchChildren decodes both nested folders and annotations")
    func fetchChildrenDecodesFoldersAndAnnotations() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/annotation-folders/4/children"))
            let json = Data("""
            {"folders": [{"id": 5, "folder_name": "Child Folder", "parent_folder": 4, "full_path": "Root/Child",
                          "child_folders_count": 0, "annotations_count": 0, "can_edit": true, "can_delete": true}],
             "annotations": [{"id": 9, "annotation": "Folder note", "annotation_type": "text", "folder": 5,
                              "transcribed": false, "transcription": null, "language": null, "translation": null}]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedAnnotationFolder.self, CachedFolderAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let folderSync = AnnotationFolderSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let response = try await folderSync.fetchChildren(folderServerID: 4)
        #expect(response.folders.count == 1)
        #expect(response.folders.first?.folderName == "Child Folder")
        #expect(response.annotations.count == 1)
        #expect(response.annotations.first?.annotation == "Folder note")
    }

    @Test("AnnotationFolderSyncService.fetchRootFolders falls back to the cache when unreachable, having cached on an earlier successful fetch")
    func fetchRootFoldersFallsBackToCacheWhenOffline() async throws {
        let container = try makeInMemoryContainer(for: [CachedAnnotationFolder.self, CachedFolderAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let folderSync = AnnotationFolderSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/session-annotation-folders") {
                let json = Data("""
                {"count": 1, "next": null, "previous": null, "results": [{"id": 1, "session": 1, "folder": 4}]}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            let json = Data("""
            {"id": 4, "folder_name": "Root Folder", "parent_folder": null, "full_path": "Root Folder",
             "child_folders_count": 0, "annotations_count": 0, "can_edit": true, "can_delete": true}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let onlineFolders = try await folderSync.fetchRootFolders(sessionServerID: 1)
        #expect(onlineFolders.count == 1)

        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let offlineFolders = try await folderSync.fetchRootFolders(sessionServerID: 1)
        #expect(offlineFolders.count == 1, "the previously-cached root folder should still be browsable offline")
        #expect(offlineFolders.first?.folderName == "Root Folder")
    }

    @Test("AnnotationFolderSyncService.fetchChildren falls back to the cache when unreachable, having cached on an earlier successful fetch")
    func fetchChildrenFallsBackToCacheWhenOffline() async throws {
        let container = try makeInMemoryContainer(for: [CachedAnnotationFolder.self, CachedFolderAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let folderSync = AnnotationFolderSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        StubURLProtocol.handler = { request in
            let json = Data("""
            {"folders": [{"id": 5, "folder_name": "Child Folder", "parent_folder": 4, "full_path": "Root/Child",
                          "child_folders_count": 0, "annotations_count": 0, "can_edit": true, "can_delete": true}],
             "annotations": [{"id": 9, "annotation": "Folder note", "annotation_type": "text", "folder": 5,
                              "transcribed": false, "transcription": null, "language": null, "translation": null}]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let onlineResponse = try await folderSync.fetchChildren(folderServerID: 4)
        #expect(onlineResponse.folders.count == 1)

        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let offlineResponse = try await folderSync.fetchChildren(folderServerID: 4)
        #expect(offlineResponse.folders.count == 1, "the previously-cached child folder should still be browsable offline")
        #expect(offlineResponse.folders.first?.folderName == "Child Folder")
        #expect(offlineResponse.annotations.count == 1)
        #expect(offlineResponse.annotations.first?.annotation == "Folder note")
    }

    @Test("AnnotationFolderSyncService.createRootFolder creates the folder then attaches it to the session")
    func createRootFolderCreatesThenAttaches() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/annotation-folders") {
                let json = Data("""
                {"id": 6, "folder_name": "New Folder", "parent_folder": null, "full_path": "New Folder",
                 "child_folders_count": 0, "annotations_count": 0, "can_edit": true, "can_delete": true}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(request.url!.path.hasSuffix("/session-annotation-folders"))
            let json = Data("""
            {"id": 2, "session": 1, "folder": 6}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedAnnotationFolder.self, CachedFolderAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let folderSync = AnnotationFolderSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let folder = try await folderSync.createRootFolder(sessionServerID: 1, folderName: "New Folder")
        #expect(folder.id == 6)
    }

    @Test("AnnotationFolderSyncService.renameFolder PATCHes the folder's detail endpoint")
    func renameFolderPatchesFolderName() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/annotation-folders/6"))
            let json = Data("""
            {"id": 6, "folder_name": "Renamed", "parent_folder": null, "full_path": "Renamed",
             "child_folders_count": 0, "annotations_count": 0, "can_edit": true, "can_delete": true}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedAnnotationFolder.self, CachedFolderAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let folderSync = AnnotationFolderSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let folder = try await folderSync.renameFolder(folderServerID: 6, folderName: "Renamed")
        #expect(folder.folderName == "Renamed")
    }

    @Test("AnnotationFolderSyncService.moveFolder PATCHes the folder's detail endpoint with a new parent")
    func moveFolderPatchesParentFolder() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/annotation-folders/6"))
            let json = Data("""
            {"id": 6, "folder_name": "Subfolder", "parent_folder": 9, "full_path": "Parent/Subfolder",
             "child_folders_count": 0, "annotations_count": 0, "can_edit": true, "can_delete": true}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedAnnotationFolder.self, CachedFolderAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let folderSync = AnnotationFolderSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let folder = try await folderSync.moveFolder(folderServerID: 6, newParentServerID: 9)
        #expect(folder.parentFolder == 9)
    }

    @Test("LocalNotebookImportService counts and imports every not-yet-synced local record, resolving parent dependencies")
    func localNotebookImportServiceImportsAllLocalRecords() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("/protocols") {
                let json = Data("""
                {"id": 77, "protocol_title": "Sample Prep", "protocol_description": null, "enabled": false, "sections": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            } else if request.url!.path.hasSuffix("/sections") {
                let json = Data("""
                {"id": 5, "section_description": "Setup", "order": 0, "section_duration": null, "steps": []}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
            let json = Data("""
            {"id": 12, "project_name": "Proteomics Study", "project_description": null}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [
            CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self, CachedSession.self,
            CachedStepReagent.self, CachedReagent.self, CachedStepAnnotation.self, CachedSessionAnnotation.self,
            CachedStoredReagent.self, CachedReagentAction.self, CachedInstrumentUsage.self, CachedProject.self,
            CachedInstrumentJob.self, OutboxEntry.self,
        ])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let protocolSync = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionSync = SessionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepReagentSync = StepReagentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let stepAnnotationSync = StepAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let inventorySync = InventorySyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentSync = InstrumentSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let projectSync = ProjectSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let instrumentJobSync = InstrumentJobSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let sessionAnnotationSync = SessionAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })
        let outbox = OutboxService(modelContainer: container, protocolSync: protocolSync, sessionSync: sessionSync, stepReagentSync: stepReagentSync, stepAnnotationSync: stepAnnotationSync, sessionAnnotationSync: sessionAnnotationSync, inventorySync: inventorySync, instrumentSync: instrumentSync, projectSync: projectSync, instrumentJobSync: instrumentJobSync)
        let importSync = LocalNotebookImportService(modelContainer: container, outboxSync: outbox)

        let context = ModelContext(container)
        let localProtocol = CachedProtocol(protocolTitle: "Sample Prep", protocolDescription: nil, enabled: false, isLocallyAuthored: true)
        context.insert(localProtocol)
        let localSection = CachedProtocolSection(sectionDescription: "Setup", order: 0, protocolModel: localProtocol)
        context.insert(localSection)
        let localProject = CachedProject(projectName: "Proteomics Study", projectDescription: nil)
        context.insert(localProject)
        try context.save()

        let count = try await importSync.countLocalOnlyRecords()
        #expect(count == 3, "the protocol, its section, and the project are all not-yet-synced")

        await importSync.importAll()

        let protocols = try context.fetch(FetchDescriptor<CachedProtocol>())
        #expect(protocols.first?.serverID == 77)
        let sections = try context.fetch(FetchDescriptor<CachedProtocolSection>())
        #expect(sections.first?.serverID == 5)
        let projects = try context.fetch(FetchDescriptor<CachedProject>())
        #expect(projects.first?.serverID == 12)

        let remainingCount = try await importSync.countLocalOnlyRecords()
        #expect(remainingCount == 0, "everything should have synced and no longer count as local-only")
    }

    @Test("TranscriptionNotificationService.webSocketURL derives ws:// from an http:// API base and preserves the port")
    func transcriptionWebSocketURLDerivesFromHTTPBase() {
        let apiBaseURL = URL(string: "http://127.0.0.1:8002/api/v1/")!
        let wsURL = TranscriptionNotificationService.webSocketURL(from: apiBaseURL, token: "abc123")
        #expect(wsURL?.absoluteString == "ws://127.0.0.1:8002/ws/ccc/notifications/?token=abc123")
    }

    @Test("TranscriptionNotificationService.webSocketURL derives wss:// from an https:// API base")
    func transcriptionWebSocketURLDerivesFromHTTPSBase() {
        let apiBaseURL = URL(string: "https://cupcake.proteo.info/api/v1/")!
        let wsURL = TranscriptionNotificationService.webSocketURL(from: apiBaseURL, token: "abc123")
        #expect(wsURL?.absoluteString == "wss://cupcake.proteo.info/ws/ccc/notifications/?token=abc123")
    }

    @Test("TranscriptionNotificationService.originHeader matches the API base's scheme, host, and port")
    func transcriptionOriginHeaderMatchesAPIBase() {
        #expect(TranscriptionNotificationService.originHeader(for: URL(string: "http://127.0.0.1:8002/api/v1/")!) == "http://127.0.0.1:8002")
        #expect(TranscriptionNotificationService.originHeader(for: URL(string: "https://cupcake.proteo.info/api/v1/")!) == "https://cupcake.proteo.info")
    }

    @Test("TranscriptionNotificationService.parseEvent decodes started, completed, and failed messages")
    func transcriptionParseEventDecodesAllThreeTypes() {
        let started = TranscriptionNotificationService.parseEvent(from: #"{"type":"transcription.started","annotation_id":42}"#)
        #expect(started == .started(annotationServerID: 42))

        let completed = TranscriptionNotificationService.parseEvent(from: #"{"type":"transcription.completed","annotation_id":42,"language":"en"}"#)
        #expect(completed == .completed(annotationServerID: 42))

        let failed = TranscriptionNotificationService.parseEvent(from: #"{"type":"transcription.failed","annotation_id":42,"error":"boom"}"#)
        #expect(failed == .failed(annotationServerID: 42, error: "boom"))
    }

    @Test("TranscriptionNotificationService.parseEvent ignores unrelated message types")
    func transcriptionParseEventIgnoresUnrelatedMessages() {
        let connectionEstablished = TranscriptionNotificationService.parseEvent(from: #"{"type":"connection.established","user_id":1}"#)
        #expect(connectionEstablished == nil)

        let malformed = TranscriptionNotificationService.parseEvent(from: "not json")
        #expect(malformed == nil)
    }

    @Test("TimeKeeperNotificationService.webSocketURL derives ws:// from an http:// API base and preserves the port")
    func timeKeeperWebSocketURLDerivesFromHTTPBase() {
        let apiBaseURL = URL(string: "http://127.0.0.1:8002/api/v1/")!
        let wsURL = TimeKeeperNotificationService.webSocketURL(from: apiBaseURL, token: "abc123")
        #expect(wsURL?.absoluteString == "ws://127.0.0.1:8002/ws/ccrv/timekeepers/?token=abc123")
    }

    @Test("TimeKeeperNotificationService.webSocketURL derives wss:// from an https:// API base")
    func timeKeeperWebSocketURLDerivesFromHTTPSBase() {
        let apiBaseURL = URL(string: "https://cupcake.proteo.info/api/v1/")!
        let wsURL = TimeKeeperNotificationService.webSocketURL(from: apiBaseURL, token: "abc123")
        #expect(wsURL?.absoluteString == "wss://cupcake.proteo.info/ws/ccrv/timekeepers/?token=abc123")
    }

    @Test("TimeKeeperNotificationService.originHeader matches the API base's scheme, host, and port")
    func timeKeeperOriginHeaderMatchesAPIBase() {
        #expect(TimeKeeperNotificationService.originHeader(for: URL(string: "http://127.0.0.1:8002/api/v1/")!) == "http://127.0.0.1:8002")
        #expect(TimeKeeperNotificationService.originHeader(for: URL(string: "https://cupcake.proteo.info/api/v1/")!) == "https://cupcake.proteo.info")
    }

    @Test("TimeKeeperNotificationService.parseEvent decodes started, stopped, and updated messages")
    func timeKeeperParseEventDecodesAllThreeTypes() {
        let started = TimeKeeperNotificationService.parseEvent(from: #"{"type":"timekeeper.started","timekeeperId":"1","sessionId":"7","stepId":"10","startTime":"2026-07-11T10:00:00Z","timestamp":"2026-07-11T10:00:00Z"}"#)
        #expect(started == .started(timeKeeperServerID: 1, sessionServerID: 7, stepServerID: 10, startTime: "2026-07-11T10:00:00Z"))

        let stopped = TimeKeeperNotificationService.parseEvent(from: #"{"type":"timekeeper.stopped","timekeeperId":"1","sessionId":"7","stepId":"10","duration":250,"durationFormatted":"4:10","timestamp":"2026-07-11T10:01:00Z"}"#)
        #expect(stopped == .stopped(timeKeeperServerID: 1, sessionServerID: 7, stepServerID: 10, duration: 250))

        let updated = TimeKeeperNotificationService.parseEvent(from: #"{"type":"timekeeper.updated","timekeeperId":"1","sessionId":"7","stepId":"10","started":true,"duration":300,"timestamp":"2026-07-11T10:02:00Z"}"#)
        #expect(updated == .updated(timeKeeperServerID: 1, sessionServerID: 7, stepServerID: 10, started: true, duration: 300))
    }

    @Test("TimeKeeperNotificationService.parseEvent ignores unrelated message types")
    func timeKeeperParseEventIgnoresUnrelatedMessages() {
        let connectionEstablished = TimeKeeperNotificationService.parseEvent(from: #"{"type":"ccrv.connection.established","userId":1}"#)
        #expect(connectionEstablished == nil)

        let malformed = TimeKeeperNotificationService.parseEvent(from: "not json")
        #expect(malformed == nil)
    }

    @Test("TimeKeeperNotificationService.Event.sessionServerID extracts the session id from any event case")
    func timeKeeperEventSessionServerIDExtractsFromAnyCase() {
        #expect(TimeKeeperNotificationService.Event.started(timeKeeperServerID: 1, sessionServerID: 7, stepServerID: nil, startTime: nil).sessionServerID == 7)
        #expect(TimeKeeperNotificationService.Event.stopped(timeKeeperServerID: 1, sessionServerID: 7, stepServerID: nil, duration: nil).sessionServerID == 7)
        #expect(TimeKeeperNotificationService.Event.updated(timeKeeperServerID: 1, sessionServerID: 7, stepServerID: nil, started: nil, duration: nil).sessionServerID == 7)
    }

    @Test("TimeKeeperSyncService.fetchTimeKeepers returns DTOs without writing to the cache")
    func timeKeeperFetchTimeKeepersDoesNotWriteCache() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.query?.contains("session=7") == true)
            let json = Data("""
            {"count": 1, "next": null, "previous": null, "results": [
                {"id": 1, "session": 7, "step": 10, "started": true, "start_time": "2026-07-11T10:00:00Z", "current_duration": 250, "original_duration": 300}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedTimeKeeper.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = TimeKeeperSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dtos = try await service.fetchTimeKeepers(sessionServerID: 7)
        #expect(dtos.count == 1)
        #expect(dtos.first?.currentDuration == 250)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedTimeKeeper>())
        #expect(cached.isEmpty, "fetchTimeKeepers is a pure network call, the caller applies results to its own context")
    }

    @Test("TimeKeeperSyncService.create POSTs session/step/durations and caches the result")
    func timeKeeperCreateCachesResult() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["session"] as? Int64 == 7)
            #expect(sentJSON["step"] as? Int64 == 10)
            #expect(sentJSON["current_duration"] as? Int == 300)
            #expect(sentJSON["original_duration"] as? Int == 300)
            let json = Data("""
            {"id": 1, "session": 7, "step": 10, "started": false, "start_time": null, "current_duration": 300, "original_duration": 300}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedProtocolStep.self, CachedTimeKeeper.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        let step = CachedProtocolStep(serverID: 10, stepDescription: "Incubate", order: 0)
        context.insert(session)
        context.insert(step)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = TimeKeeperSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let serverID = try await service.create(sessionServerID: 7, sessionClientID: session.clientID, stepServerID: 10, stepClientID: step.clientID, durationSeconds: 300)
        #expect(serverID == 1)

        let cached = try context.fetch(FetchDescriptor<CachedTimeKeeper>()).first
        #expect(cached?.currentDuration == 300)
        #expect(cached?.started == false)
    }

    @Test("TimeKeeperSyncService.startTimer/stopTimer/resetTimer hit the right action endpoints and update the cache")
    func timeKeeperActionsUpdateCache() async throws {
        nonisolated(unsafe) var hitPaths: [String] = []
        StubURLProtocol.handler = { request in
            hitPaths.append(request.url!.path)
            let json = Data("""
            {"time_keeper": {"id": 1, "session": 7, "step": 10, "started": true, "start_time": "2026-07-11T10:00:00Z", "current_duration": 300, "original_duration": 300}}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSession.self, CachedTimeKeeper.self])
        let context = ModelContext(container)
        let session = CachedSession(serverID: 7, name: "Run 1", enabled: true, isRunning: true, status: "running")
        context.insert(session)
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = TimeKeeperSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await service.startTimer(serverID: 1)
        #expect(dto.started)
        #expect(hitPaths.last?.hasSuffix("/time-keepers/1/start_timer") == true)

        let cached = try context.fetch(FetchDescriptor<CachedTimeKeeper>()).first
        #expect(cached?.started == true)
        #expect(cached?.startTime == "2026-07-11T10:00:00Z")
    }

    @Test("ProtocolSyncService.fetchProtocolIDs hits the right filtered-browsing endpoint")
    func protocolFetchProtocolIDsHitsRightEndpoint() async throws {
        nonisolated(unsafe) var hitPath: String?
        StubURLProtocol.handler = { request in
            hitPath = request.url!.path
            let json = Data("""
            [{"id": 10, "protocol_title": "A", "enabled": true, "sections": []}, {"id": 11, "protocol_title": "B", "enabled": true, "sections": []}]
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let ids = try await service.fetchProtocolIDs(filter: .myProtocols)
        #expect(ids == [10, 11])
        #expect(hitPath?.hasSuffix("/protocols/my_protocols") == true)
    }

    @Test("ProtocolSyncService.importFromProtocolsIO POSTs the URL and caches the imported protocol")
    func protocolImportFromProtocolsIOCachesResult() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["url"] as? String == "https://www.protocols.io/view/example")
            let json = Data("""
            {"id": 99, "protocol_title": "Imported Protocol", "enabled": false, "sections": []}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let clientID = try await service.importFromProtocolsIO(url: "https://www.protocols.io/view/example")

        let context = ModelContext(container)
        let cached = try context.fetch(FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.clientID == clientID })).first
        #expect(cached?.serverID == 99)
        #expect(cached?.protocolTitle == "Imported Protocol")
    }

    @Test("ProtocolSyncService.fetchExportURL parses the signed download URL")
    func protocolFetchExportURLParsesResponse() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.path.hasSuffix("/protocols/40/get_export_url"))
            let json = Data(#"{"download_url": "https://example.test/api/v1/protocols/40/export_html/?token=abc"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocol.self, CachedProtocolSection.self, CachedProtocolStep.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ProtocolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let url = try await service.fetchExportURL(protocolServerID: 40, sessionServerID: nil)
        #expect(url.absoluteString == "https://example.test/api/v1/protocols/40/export_html/?token=abc")
    }

    @Test("MaintenanceLogSyncService.create POSTs the right body and caches the result")
    func maintenanceLogCreateCachesResult() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["instrument"] as? Int64 == 1)
            #expect(sentJSON["maintenance_type"] as? String == "routine")
            #expect(sentJSON["status"] as? String == "pending")
            let json = Data("""
            {"id": 5, "instrument": 1, "instrument_name": "Test Centrifuge", "maintenance_date": "2026-07-12T10:00:00Z",
             "maintenance_type": "routine", "status": "pending", "maintenance_description": "Routine check", "maintenance_notes": null, "is_template": false}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMaintenanceLog.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = MaintenanceLogSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let serverID = try await service.create(
            instrumentServerID: 1,
            maintenanceDate: "2026-07-12T10:00:00Z",
            maintenanceType: "routine",
            status: "pending",
            maintenanceDescription: "Routine check",
            maintenanceNotes: nil
        )
        #expect(serverID == 5)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedMaintenanceLog>()).first
        #expect(cached?.instrumentName == "Test Centrifuge")
        #expect(cached?.status == "pending")
    }

    @Test("MaintenanceLogSyncService.updateStatus PATCHes status and updates the cache")
    func maintenanceLogUpdateStatusUpdatesCache() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["status"] as? String == "completed")
            let json = Data("""
            {"id": 5, "instrument": 1, "instrument_name": "Test Centrifuge", "maintenance_date": null,
             "maintenance_type": "routine", "status": "completed", "maintenance_description": null, "maintenance_notes": null, "is_template": false}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedMaintenanceLog.self])
        let context = ModelContext(container)
        context.insert(CachedMaintenanceLog(serverID: 5, instrumentServerID: 1, instrumentName: "Test Centrifuge", status: "pending"))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = MaintenanceLogSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await service.updateStatus(serverID: 5, status: "completed")
        #expect(dto.status == "completed")

        let cached = try context.fetch(FetchDescriptor<CachedMaintenanceLog>()).first
        #expect(cached?.status == "completed")
    }

    @Test("StepVariationSyncService.create POSTs the right body and caches the result")
    func stepVariationCreateCachesResult() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["step"] as? Int64 == 6)
            #expect(sentJSON["variation_duration"] as? Int == 1200)
            let json = Data("""
            {"id": 1, "step": 6, "variation_description": "For larger samples, extend incubation.", "variation_duration": 1200}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStepVariation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepVariationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let serverID = try await service.create(stepServerID: 6, variationDescription: "For larger samples, extend incubation.", variationDuration: 1200)
        #expect(serverID == 1)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedStepVariation>()).first
        #expect(cached?.variationDuration == 1200)
    }

    @Test("StepVariationSyncService.create scopes a variation to a session when given one, and refetch filters by it")
    func stepVariationCreateAndRefetchScopeToSession() async throws {
        StubURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                let body = try #require(request.httpBodyStream).readAllData()
                let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(sentJSON["step"] as? Int64 == 6)
                #expect(sentJSON["session"] as? Int64 == 10)
                let json = Data("""
                {"id": 2, "step": 6, "session": 10, "variation_description": "For one experiment only", "variation_duration": 600}
                """.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(request.url?.query?.contains("session=10") == true)
            let json = Data("""
            {"count": 1, "next": null, "previous": null, "results": [
                {"id": 2, "step": 6, "session": 10, "variation_description": "For one experiment only", "variation_duration": 600}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStepVariation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StepVariationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let serverID = try await service.create(stepServerID: 6, sessionServerID: 10, variationDescription: "For one experiment only", variationDuration: 600)
        #expect(serverID == 2)

        var cached = try ModelContext(container).fetch(FetchDescriptor<CachedStepVariation>()).first
        #expect(cached?.sessionServerID == 10)

        try await service.refetch(stepServerID: 6, sessionServerID: 10)
        cached = try ModelContext(container).fetch(FetchDescriptor<CachedStepVariation>()).first
        #expect(cached?.sessionServerID == 10)
    }

    @Test("ProtocolRatingSyncService.rate creates a new rating when none exists yet")
    func protocolRatingCreatesWhenNoneExists() async throws {
        StubURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                let json = Data(#"{"count": 0, "next": null, "previous": null, "results": []}"#.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(request.httpMethod == "POST")
            let json = Data(#"{"id": 1, "protocol": 40, "complexity_rating": 5, "duration_rating": 3}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocolRating.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ProtocolRatingSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await service.rate(protocolServerID: 40, userID: 1, complexityRating: 5, durationRating: 3)
        #expect(dto.id == 1)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedProtocolRating>()).first
        #expect(cached?.complexityRating == 5)
    }

    @Test("ProtocolRatingSyncService.rate PATCHes the existing rating rather than risking a duplicate POST")
    func protocolRatingPatchesWhenAlreadyExists() async throws {
        nonisolated(unsafe) var sawPost = false
        StubURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                let json = Data(#"{"count": 1, "next": null, "previous": null, "results": [{"id": 7, "protocol": 40, "complexity_rating": 2, "duration_rating": 2}]}"#.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            if request.httpMethod == "POST" { sawPost = true }
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/ratings/7"))
            let json = Data(#"{"id": 7, "protocol": 40, "complexity_rating": 8, "duration_rating": 9}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedProtocolRating.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ProtocolRatingSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await service.rate(protocolServerID: 40, userID: 1, complexityRating: 8, durationRating: 9)
        #expect(dto.complexityRating == 8)
        #expect(!sawPost, "must never POST a duplicate rating once one is known to exist")
    }

    @Test("StoredReagentAnnotationSyncService.create posts the annotation_data shortcut and caches the result")
    func storedReagentAnnotationCreateCachesResult() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["stored_reagent"] as? Int64 == 1)
            #expect(sentJSON["folder"] as? Int64 == 2)
            let annotationData = try #require(sentJSON["annotation_data"] as? [String: Any])
            #expect(annotationData["annotation"] as? String == "MSDS sheet notes")
            let json = Data("""
            {"id": 9, "stored_reagent": 1, "folder": 2, "folder_name": "Certificates",
             "annotation_text": "MSDS sheet notes", "annotation_type": "text", "scratched": false}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStoredReagentAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StoredReagentAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let serverID = try await service.create(storedReagentServerID: 1, folderServerID: 2, text: "MSDS sheet notes")
        #expect(serverID == 9)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedStoredReagentAnnotation>()).first
        #expect(cached?.folderName == "Certificates")
        #expect(cached?.annotationText == "MSDS sheet notes")
    }

    @Test("StoredReagentAnnotationSyncService.fetchDocumentFolders filters to MSDS/Certificates/Manuals")
    func storedReagentAnnotationFetchDocumentFoldersFilters() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url!.query?.contains("resource_type=file") == true)
            let json = Data("""
            {"count": 4, "next": null, "previous": null, "results": [
              {"id": 1, "folder_name": "MSDS", "can_edit": true, "can_delete": true},
              {"id": 2, "folder_name": "Certificates", "can_edit": true, "can_delete": true},
              {"id": 3, "folder_name": "Manuals", "can_edit": true, "can_delete": true},
              {"id": 4, "folder_name": "Unrelated", "can_edit": true, "can_delete": true}
            ]}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedStoredReagentAnnotation.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = StoredReagentAnnotationSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let folders = try await service.fetchDocumentFolders()
        #expect(folders.count == 3)
        #expect(folders.map(\.folderName).sorted() == ["Certificates", "MSDS", "Manuals"].sorted())
    }

    @Test("ReagentSubscriptionSyncService.subscribe creates a new subscription when none exists, always sending user explicitly")
    func reagentSubscriptionCreatesWhenNoneExists() async throws {
        StubURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                let json = Data(#"{"count": 0, "next": null, "previous": null, "results": []}"#.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            #expect(request.httpMethod == "POST")
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["user"] as? Int64 == 1, "must always send user explicitly, perform_create's auto-assign runs after required-field validation")
            let json = Data(#"{"id": 3, "user": 1, "stored_reagent": 1, "notify_on_low_stock": true, "notify_on_expiry": false}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedReagentSubscription.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ReagentSubscriptionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await service.subscribe(storedReagentServerID: 1, userID: 1, notifyOnLowStock: true, notifyOnExpiry: false)
        #expect(dto.id == 3)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedReagentSubscription>()).first
        #expect(cached?.notifyOnLowStock == true)
    }

    @Test("ReagentSubscriptionSyncService.subscribe PATCHes the existing subscription rather than risking a duplicate POST")
    func reagentSubscriptionPatchesWhenAlreadyExists() async throws {
        nonisolated(unsafe) var sawPost = false
        StubURLProtocol.handler = { request in
            if request.httpMethod == "GET" {
                let json = Data(#"{"count": 1, "next": null, "previous": null, "results": [{"id": 5, "user": 1, "stored_reagent": 1, "notify_on_low_stock": true, "notify_on_expiry": false}]}"#.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
            }
            if request.httpMethod == "POST" { sawPost = true }
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/reagent-subscriptions/5"))
            let json = Data(#"{"id": 5, "user": 1, "stored_reagent": 1, "notify_on_low_stock": false, "notify_on_expiry": true}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedReagentSubscription.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = ReagentSubscriptionSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await service.subscribe(storedReagentServerID: 1, userID: 1, notifyOnLowStock: false, notifyOnExpiry: true)
        #expect(dto.notifyOnExpiry == true)
        #expect(!sawPost, "must never POST a duplicate subscription once one is known to exist")
    }

    @Test("SamplePoolSyncService.create POSTs the right body and caches the result")
    func samplePoolCreateCachesResult() async throws {
        StubURLProtocol.handler = { request in
            let body = try #require(request.httpBodyStream).readAllData()
            let sentJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(sentJSON["metadata_table"] as? Int64 == 6)
            #expect(sentJSON["pool_name"] as? String == "Pool A")
            #expect(sentJSON["pooled_only_samples"] as? [Int] == [1, 2])
            #expect(sentJSON["pooled_and_independent_samples"] as? [Int] == [3])
            let json = Data("""
            {"id": 1, "pool_name": "Pool A", "pool_description": "First pool", "pooled_only_samples": [1, 2],
             "pooled_and_independent_samples": [3], "is_reference": false, "sdrf_value": "SN=sample 1,sample 2,sample 3",
             "metadata_table": 6, "total_samples": 3}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSamplePool.self])
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SamplePoolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let serverID = try await service.create(
            metadataTableServerID: 6,
            poolName: "Pool A",
            poolDescription: "First pool",
            pooledOnlySamples: [1, 2],
            pooledAndIndependentSamples: [3],
            isReference: false
        )
        #expect(serverID == 1)

        let cached = try ModelContext(container).fetch(FetchDescriptor<CachedSamplePool>()).first
        #expect(cached?.totalSamples == 3)
        #expect(cached?.sdrfValue == "SN=sample 1,sample 2,sample 3")
    }

    @Test("SamplePoolSyncService.update PATCHes the right path and updates the cache")
    func samplePoolUpdateUpdatesCache() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url!.path.hasSuffix("/sample-pools/1"))
            let json = Data("""
            {"id": 1, "pool_name": "Pool A Renamed", "pool_description": "First pool", "pooled_only_samples": [1, 2],
             "pooled_and_independent_samples": [3], "is_reference": true, "sdrf_value": "SN=sample 1,sample 2,sample 3",
             "metadata_table": 6, "total_samples": 3}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let container = try makeInMemoryContainer(for: [CachedSamplePool.self])
        let context = ModelContext(container)
        context.insert(CachedSamplePool(serverID: 1, metadataTableServerID: 6, poolName: "Pool A", pooledOnlySamples: [1, 2], pooledAndIndependentSamples: [3]))
        try context.save()

        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = SamplePoolSyncService(modelContainer: container, apiClient: apiClient, deviceToken: { "test-token" })

        let dto = try await service.update(serverID: 1, poolName: "Pool A Renamed", poolDescription: "First pool", pooledOnlySamples: [1, 2], pooledAndIndependentSamples: [3], isReference: true)
        #expect(dto.poolName == "Pool A Renamed")

        let cached = try context.fetch(FetchDescriptor<CachedSamplePool>()).first
        #expect(cached?.poolName == "Pool A Renamed")
        #expect(cached?.isReference == true)
    }

    @Test("AsyncTaskDTO decodes the real hand-rolled retrieve response shape")
    func asyncTaskDTODecodesRetrieveShape() throws {
        let json = Data(#"""
            {"id": "cc51e477-2206-4750-b629-315a04d49ba7", "task_type": "EXPORT_SDRF", "status": "SUCCESS",
             "metadata_table_id": 277, "metadata_table_name": "Browser Flow Table", "parameters": {}, "result": {},
             "progress_percentage": 100, "progress_description": "", "created_at": "2026-07-26T13:01:06Z",
             "started_at": "2026-07-26T13:03:26Z", "completed_at": "2026-07-26T13:03:26Z", "duration": 0.03,
             "error_message": "", "traceback": null}
            """#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(AsyncTaskDTO.self, from: json)
        #expect(dto.id == "cc51e477-2206-4750-b629-315a04d49ba7")
        #expect(dto.metadataTableID == 277)
        #expect(dto.status == "SUCCESS")
        #expect(dto.isTerminal == true)
    }

    @Test("AsyncTaskDTO decodes the lightweight list response shape (metadata_table, not metadata_table_id)")
    func asyncTaskDTODecodesListShape() throws {
        let json = Data(#"""
            {"id": "cc51e477-2206-4750-b629-315a04d49ba7", "task_type": "EXPORT_SDRF", "task_type_display": "Export SDRF File",
             "status": "QUEUED", "status_display": "Queued", "user": 1, "user_username": "testuser",
             "metadata_table": 277, "metadata_table_name": "Browser Flow Table", "progress_percentage": 0,
             "progress_description": "", "created_at": "2026-07-26T13:01:06Z", "started_at": null,
             "completed_at": null, "duration": null, "error_message": ""}
            """#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(AsyncTaskDTO.self, from: json)
        #expect(dto.metadataTableID == 277)
        #expect(dto.status == "QUEUED")
        #expect(dto.isTerminal == false)
    }

    @Test("AsyncTaskSyncService.fetchAll GETs the real paginated endpoint")
    func asyncTaskFetchAllGetsRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url!.path.hasSuffix("/async-tasks"))
            let json = Data(#"""
                {"count": 1, "next": null, "previous": null, "results": [
                  {"id": "abc", "task_type": "EXPORT_SDRF", "status": "SUCCESS", "metadata_table": 1,
                   "metadata_table_name": "T", "progress_percentage": 100, "progress_description": "",
                   "created_at": "2026-01-01T00:00:00Z", "started_at": null, "completed_at": null,
                   "duration": null, "error_message": ""}
                ]}
                """#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })
        let page = try await service.fetchAll()
        #expect(page.count == 1)
        #expect(page.results.first?.id == "abc")
    }

    @Test("AsyncTaskSyncService.exportSDRFFile POSTs the real request shape and returns the task id")
    func asyncTaskExportSDRFPostsRealShape() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/async-export/sdrf_file"))
            let body = request.httpBodyStream?.readAllData() ?? request.httpBody ?? Data()
            let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(decoded?["metadata_table_id"] as? Int64 == 277)
            #expect(decoded?["sample_number"] as? Int == 5)
            let columnIds = (decoded?["metadata_column_ids"] as? [Int]) ?? []
            #expect(columnIds == [1, 2], "the real DRF field is metadata_column_ids (lowercase ids), not metadata_column_i_ds")
            let json = Data(#"{"task_id": "cc51e477-2206-4750-b629-315a04d49ba7", "message": "queued"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })
        let taskID = try await service.exportSDRFFile(metadataTableServerID: 277, metadataColumnIDs: [1, 2], sampleNumber: 5, includePools: false)
        #expect(taskID == "cc51e477-2206-4750-b629-315a04d49ba7")
    }

    @Test("AsyncTaskSyncService.cancel DELETEs the real cancel endpoint")
    func asyncTaskCancelDeletesRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url!.path.hasSuffix("/async-tasks/abc/cancel"))
            let json = Data(#"{"message": "Task deleted successfully"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })
        try await service.cancel(id: "abc")
    }

    @Test("AsyncTaskSyncService.fetchDownloadURL GETs the real download_url action")
    func asyncTaskFetchDownloadURLGetsRealEndpoint() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url!.path.hasSuffix("/async-tasks/abc/download_url"))
            let json = Data(#"""
                {"download_url": "https://example.test/api/v1/async-tasks/abc/download/?token=xyz",
                 "filename": "export.sdrf.tsv", "content_type": "text/tab-separated-values", "file_size": 42}
                """#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })
        let info = try await service.fetchDownloadURL(id: "abc")
        #expect(info.filename == "export.sdrf.tsv")
    }

    @Test("AsyncTaskNotificationService.webSocketURL derives ws:// from an http:// API base and preserves the port")
    func asyncTaskWebSocketURLDerivesFromHTTPBase() {
        let apiBaseURL = URL(string: "http://127.0.0.1:8002/api/v1/")!
        let wsURL = AsyncTaskNotificationService.webSocketURL(from: apiBaseURL, token: "abc123")
        #expect(wsURL?.absoluteString == "ws://127.0.0.1:8002/ws/ccc/notifications/?token=abc123")
    }

    @Test("AsyncTaskNotificationService.originHeader matches the API base's scheme, host, and port")
    func asyncTaskOriginHeaderMatchesAPIBase() {
        #expect(AsyncTaskNotificationService.originHeader(for: URL(string: "http://127.0.0.1:8002/api/v1/")!) == "http://127.0.0.1:8002")
    }

    @Test("AsyncTaskNotificationService.parseEvent decodes a real async_task.update push message")
    func asyncTaskParseEventDecodesRealPush() {
        let event = AsyncTaskNotificationService.parseEvent(from: #"""
            {"type": "async_task.update", "task_id": "cc51e477-2206-4750-b629-315a04d49ba7", "task_type": "EXPORT_SDRF",
             "status": "SUCCESS", "progress_percentage": 100, "progress_description": "", "error_message": "",
             "result": {"file_url": "https://example.test/download"}, "download_url": null, "timestamp": "2026-07-26T13:03:26Z"}
            """#)
        #expect(event?.taskID == "cc51e477-2206-4750-b629-315a04d49ba7")
        #expect(event?.status == "SUCCESS")
        #expect(event?.progressPercentage == 100)
    }

    @Test("AsyncTaskNotificationService.parseEvent ignores unrelated message types")
    func asyncTaskParseEventIgnoresUnrelatedMessages() {
        let subscriptionConfirmed = AsyncTaskNotificationService.parseEvent(from: #"{"type":"subscription.confirmed","subscription_type":"async_task_updates"}"#)
        #expect(subscriptionConfirmed == nil)

        let malformed = AsyncTaskNotificationService.parseEvent(from: "not json")
        #expect(malformed == nil)
    }

    @Test("AsyncTaskSyncService.importSDRFFile POSTs a real multipart request with the right fields and returns the task id")
    func asyncTaskImportSDRFPostsRealMultipartShape() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url!.path.hasSuffix("/async-import/sdrf_file"))
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
            let body = request.httpBodyStream?.readAllData() ?? request.httpBody ?? Data()
            let bodyString = String(data: body, encoding: .utf8) ?? ""
            #expect(bodyString.contains("name=\"metadata_table_id\""))
            #expect(bodyString.contains("name=\"replace_existing\""))
            #expect(bodyString.contains("true"))
            #expect(bodyString.contains("name=\"import_type\""))
            #expect(bodyString.contains("user_metadata"))
            #expect(bodyString.contains("name=\"file\"; filename=\""))
            let json = Data(#"{"task_id": "f124ab05-c988-465d-ac16-e5c86d3fdc26", "message": "queued"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sdrf.tsv")
        try Data("source name\tcharacteristics[organism]\nHCC-001\thomo sapiens\n".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let taskID = try await service.importSDRFFile(metadataTableServerID: 290, fileURL: tempFile, replaceExisting: true)
        #expect(taskID == "f124ab05-c988-465d-ac16-e5c86d3fdc26")
    }

    @Test("AsyncTaskSyncService.importSDRFFile sends the real import_type value when a non-default scope is chosen, e.g. a staff user explicitly opting into touching staff-only columns")
    func asyncTaskImportSendsBothScopeWhenExplicitlyRequested() async throws {
        StubURLProtocol.handler = { request in
            let body = request.httpBodyStream?.readAllData() ?? request.httpBody ?? Data()
            let bodyString = String(data: body, encoding: .utf8) ?? ""
            #expect(bodyString.contains("name=\"import_type\""))
            #expect(bodyString.contains("\r\n\r\nboth\r\n"))
            #expect(!bodyString.contains("\r\n\r\nuser_metadata\r\n"), "the request should carry the real chosen scope, not the default")
            let json = Data(#"{"task_id": "f124ab05-c988-465d-ac16-e5c86d3fdc26", "message": "queued"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sdrf.tsv")
        try Data("source name\n".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try await service.importSDRFFile(metadataTableServerID: 290, fileURL: tempFile, replaceExisting: false, importScope: .both)
    }

    @Test("AsyncTaskSyncService.importSDRFFile surfaces the real permission-denied message for a non-owner, non-staff user")
    func asyncTaskImportSurfacesRealPermissionDeniedMessage() async throws {
        StubURLProtocol.handler = { request in
            let json = Data(#"{"error": "Permission denied: cannot edit this metadata table"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sdrf.tsv")
        try Data("source name\n".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            _ = try await service.importSDRFFile(metadataTableServerID: 290, fileURL: tempFile, replaceExisting: false)
            Issue.record("Expected the import to throw for a permission-denied response")
        } catch {
            #expect(error.userFacingMessage == "Permission denied: cannot edit this metadata table")
        }
    }

    @Test("AsyncTaskSyncService.exportSDRFFile also surfaces a real 403 error message the same way")
    func asyncTaskExportSurfacesRealPermissionDeniedMessage() async throws {
        StubURLProtocol.handler = { request in
            let json = Data(#"{"error": "Permission denied: cannot view this metadata table"}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, json)
        }
        let apiClient = APIClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: StubURLProtocol.makeSession())
        let service = AsyncTaskSyncService(apiClient: apiClient, deviceToken: { "test-token" })

        do {
            _ = try await service.exportSDRFFile(metadataTableServerID: 290, metadataColumnIDs: [], sampleNumber: 1, includePools: false)
            Issue.record("Expected the export to throw for a permission-denied response")
        } catch {
            #expect(error.userFacingMessage == "Permission denied: cannot view this metadata table")
        }
    }

}
