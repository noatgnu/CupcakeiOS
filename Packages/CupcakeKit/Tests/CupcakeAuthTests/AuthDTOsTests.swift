import Foundation
import Testing

@testable import CupcakeAuth

@Suite("Auth DTO decoding")
struct AuthDTOsTests {
    private func snakeCaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @Test("decodes the literal auth/login/ response shape")
    func decodesLoginResponse() throws {
        let json = Data("""
        {
            "access_token": "jwt-access",
            "refresh_token": "jwt-refresh",
            "user": {
                "id": 1,
                "username": "testuser",
                "email": "testuser@example.com",
                "first_name": "Test",
                "last_name": "User",
                "is_staff": false,
                "is_superuser": false,
                "date_joined": "2026-01-01T00:00:00Z",
                "last_login": null
            }
        }
        """.utf8)

        let response = try snakeCaseDecoder().decode(LoginResponse.self, from: json)

        #expect(response.accessToken == "jwt-access")
        #expect(response.refreshToken == "jwt-refresh")
        #expect(response.user.username == "testuser")
        #expect(response.user.isStaff == false)
    }

    @Test("decodes the literal device-tokens/ create response shape")
    func decodesDeviceTokenResponse() throws {
        let json = Data("""
        {
            "id": 7,
            "token": "abcdef0123456789",
            "label": "Toan's iPhone",
            "description": "",
            "permission": "write",
            "enabled": true,
            "user": 1,
            "username": "testuser",
            "created_at": "2026-01-01T00:00:00Z",
            "last_used_at": null,
            "expires_at": null,
            "is_expired": false
        }
        """.utf8)

        let dto = try snakeCaseDecoder().decode(DeviceTokenDTO.self, from: json)

        #expect(dto.token == "abcdef0123456789")
        #expect(dto.permission == "write")
        #expect(dto.expiresAt == nil)
        #expect(dto.isExpired == false)
    }
}
