import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("Protocol DTO decoding")
struct ProtocolDTOsTests {
    @Test("decodes the literal ProtocolModelSerializer shape, including nested sections/steps")
    func decodesNestedProtocol() throws {
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

    @Test("decodes a real POST protocols/ create response, which omits `sections` entirely")
    func decodesCreateResponseMissingSections() throws {
        // Captured verbatim from a real 201 response body, which has no `sections` key at all.
        let json = Data("""
        {
            "id": 16,
            "protocol_id": null,
            "protocol_created_on": "2026-07-05T22:24:11.419052Z",
            "protocol_doi": null,
            "protocol_title": "Live Backend Test Protocol",
            "protocol_url": null,
            "protocol_version_uri": null,
            "protocol_description": "",
            "enabled": false,
            "model_hash": null,
            "owner": 1,
            "editors": [],
            "viewers": [],
            "remote_id": null,
            "remote_host": null,
            "is_vaulted": false,
            "created_at": "2026-07-05T22:24:11.419022Z",
            "updated_at": "2026-07-05T22:24:11.419037Z"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(ProtocolDTO.self, from: json)

        #expect(dto.id == 16)
        #expect(dto.protocolTitle == "Live Backend Test Protocol")
        #expect(dto.sections.isEmpty)
    }
}
