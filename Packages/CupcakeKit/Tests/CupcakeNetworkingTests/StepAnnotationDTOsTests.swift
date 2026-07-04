import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("StepAnnotation DTO decoding")
struct StepAnnotationDTOsTests {
    @Test("decodes the literal StepAnnotationSerializer shape")
    func decodesStepAnnotation() throws {
        // Matches ccrv/serializers.py's StepAnnotationSerializer.Meta.fields verbatim (trimmed).
        let json = Data("""
        {
            "id": 100,
            "session": 7,
            "step": 10,
            "annotation": 55,
            "annotation_text": "Gloves are on.",
            "annotation_type": "text",
            "order": 0
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(StepAnnotationDTO.self, from: json)

        #expect(dto.id == 100)
        #expect(dto.session == 7)
        #expect(dto.step == 10)
        #expect(dto.annotationText == "Gloves are on.")
        #expect(dto.annotationType == "text")
    }

    @Test("encodes the annotation_data create shortcut as snake_case")
    func encodesCreateRequest() throws {
        let request = CreateStepAnnotationRequest(
            session: 7,
            step: 10,
            annotationData: AnnotationDataRequest(annotation: "Gloves are on.")
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"annotation_data\""))
        #expect(json.contains("\"annotation_type\":\"text\""))
        #expect(json.contains("\"auto_transcribe\":false"))
    }
}
