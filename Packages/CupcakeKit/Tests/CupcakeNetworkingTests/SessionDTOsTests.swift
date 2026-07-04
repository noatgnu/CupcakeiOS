import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("Session DTO decoding")
struct SessionDTOsTests {
    @Test("decodes the literal SessionSerializer shape — id is the lookup key, not unique_id")
    func decodesSession() throws {
        // Matches ccrv/serializers.py's SessionSerializer.Meta.fields verbatim (trimmed).
        let json = Data("""
        {
            "id": 7,
            "unique_id": "3f9c1f2e-1234-4a5b-8c6d-abcdef012345",
            "name": "Run 1",
            "enabled": true,
            "processing": false,
            "started_at": null,
            "ended_at": null,
            "is_running": false,
            "status": "ready",
            "protocols": [42]
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(SessionDTO.self, from: json)

        #expect(dto.id == 7)
        #expect(dto.uniqueId == "3f9c1f2e-1234-4a5b-8c6d-abcdef012345")
        #expect(dto.status == "ready")
        #expect(dto.protocols == [42])
    }
}
