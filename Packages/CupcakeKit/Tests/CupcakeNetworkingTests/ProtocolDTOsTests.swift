import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("Protocol DTO decoding")
struct ProtocolDTOsTests {
    @Test("decodes the literal ProtocolModelSerializer shape, including nested sections/steps")
    func decodesNestedProtocol() throws {
        // Matches ccrv/serializers.py's ProtocolModelSerializer.Meta.fields verbatim (trimmed
        // to the fields this DTO actually declares).
        let json = Data("""
        {
            "id": 42,
            "protocol_id": null,
            "protocol_title": "Sample prep",
            "protocol_description": "Prepare the sample for analysis.",
            "enabled": true,
            "sections": [
                {
                    "id": 1,
                    "section_description": "Setup",
                    "order": 0,
                    "steps": [
                        {"id": 10, "step_description": "Put on gloves", "order": 0},
                        {"id": 11, "step_description": "Label tubes", "order": 1}
                    ]
                }
            ]
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(ProtocolDTO.self, from: json)

        #expect(dto.id == 42)
        #expect(dto.protocolTitle == "Sample prep")
        #expect(dto.sections.count == 1)
        #expect(dto.sections[0].steps.map(\.stepDescription) == ["Put on gloves", "Label tubes"])
    }
}
