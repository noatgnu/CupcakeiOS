import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("APIError.userFacingMessage")
struct APIErrorTests {
    @Test("extracts a field validation error — confirmed live shape: values are always arrays")
    func extractsFieldValidationError() {
        let body = Data("""
        {"lab_group": ["Lab group is required when staff members are assigned to the job"]}
        """.utf8)
        let error = APIError.http(status: 400, body: body)
        #expect(error.userFacingMessage.contains("Lab group is required when staff members are assigned to the job"))
    }

    @Test("extracts a non_field_errors overlap rejection without a redundant field-name prefix")
    func extractsNonFieldError() {
        let body = Data("""
        {"non_field_errors": ["This instrument does not allow overlapping bookings. There are 1 existing booking(s) during this time period."]}
        """.utf8)
        let error = APIError.http(status: 400, body: body)
        let message = error.userFacingMessage
        #expect(message.contains("This instrument does not allow overlapping bookings"))
        #expect(!message.contains("non_field_errors:"))
    }

    @Test("extracts a plain-string detail permission error without a redundant field-name prefix")
    func extractsDetailError() {
        let body = Data("""
        {"detail": "You do not have permission to link this instrument usage"}
        """.utf8)
        let error = APIError.http(status: 403, body: body)
        let message = error.userFacingMessage
        #expect(message.contains("You do not have permission to link this instrument usage"))
        #expect(!message.contains("detail:"))
    }

    @Test("falls back to localizedDescription for a non-JSON body")
    func fallsBackForNonJSONBody() {
        let body = Data("not json at all".utf8)
        let error = APIError.http(status: 500, body: body)
        #expect(!error.userFacingMessage.isEmpty)
    }

    @Test("falls back to localizedDescription for a non-.http case")
    func fallsBackForTransportError() {
        let error = APIError.transport(underlying: URLError(.notConnectedToInternet))
        #expect(!error.userFacingMessage.isEmpty)
    }
}
