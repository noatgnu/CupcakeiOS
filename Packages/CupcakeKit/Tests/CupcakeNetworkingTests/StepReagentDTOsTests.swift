import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("StepReagent DTO decoding")
struct StepReagentDTOsTests {
    @Test("decodes the literal StepReagentSerializer shape, including the nested reagent object")
    func decodesStepReagent() throws {
        let json = Data("""
        {
            "id": 1, "step": 10,
            "reagent": {"id": 2, "name": "NaCl", "unit": "g"},
            "quantity": 5.0, "scalable": true, "scalable_factor": 2.0
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dto = try decoder.decode(StepReagentDTO.self, from: json)

        #expect(dto.step == 10)
        #expect(dto.reagent.name == "NaCl")
        #expect(dto.quantity == 5.0)
        #expect(dto.scalable == true)
        #expect(dto.scalableFactor == 2.0)
    }
}
