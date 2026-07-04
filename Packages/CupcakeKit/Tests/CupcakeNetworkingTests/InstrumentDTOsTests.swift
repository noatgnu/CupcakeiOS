import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("Instrument DTO decoding")
struct InstrumentDTOsTests {
    private func snakeCaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @Test("decodes the literal InstrumentSerializer shape")
    func decodesInstrument() throws {
        let json = Data("""
        {
            "id": 1, "instrument_name": "Mass Spec 1", "instrument_description": "Orbitrap",
            "enabled": true, "accepts_bookings": true, "allow_overlapping_bookings": false,
            "maintenance_overdue": false
        }
        """.utf8)
        let dto = try snakeCaseDecoder().decode(InstrumentDTO.self, from: json)
        #expect(dto.instrumentName == "Mass Spec 1")
        #expect(dto.maintenanceOverdue == false)
    }

    @Test("decodes the literal InstrumentUsageSerializer shape, including nullable time fields and decimal-as-string usage_hours")
    func decodesInstrumentUsage() throws {
        let json = Data("""
        {
            "id": 1, "instrument": 1, "instrument_name": "Mass Spec 1",
            "time_started": null, "time_ended": null, "usage_hours": "2.50",
            "description": "Sample run", "approved": false, "maintenance": false
        }
        """.utf8)
        let dto = try snakeCaseDecoder().decode(InstrumentUsageDTO.self, from: json)
        #expect(dto.timeStarted == nil)
        #expect(dto.usageHours == "2.50")
    }
}
