import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("Session DTO decoding")
struct SessionDTOsTests {
    @Test("decodes the literal SessionSerializer shape — id is the lookup key, not unique_id")
    func decodesSession() throws {
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

    @Test("decodes a real POST sessions/ create response, which omits `status` (and every other field beyond the bare essentials)")
    func decodesCreateResponseMissingStatus() throws {
        let json = Data("""
        {
            "id": 1,
            "unique_id": "32b50500-618f-4e7e-bdaa-d5d7aac3baab",
            "name": "test session",
            "enabled": false,
            "owner": 1,
            "protocols": [],
            "editors": [],
            "viewers": [],
            "remote_id": null,
            "remote_host": null,
            "created_at": "2026-07-05T22:51:18.030503Z",
            "updated_at": "2026-07-05T22:51:18.030508Z"
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(SessionDTO.self, from: json)

        #expect(dto.id == 1)
        #expect(dto.status == nil)
        #expect(dto.protocols.isEmpty)
    }
}
