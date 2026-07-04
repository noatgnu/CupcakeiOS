import Foundation
import Testing

@testable import CupcakeNetworking

@Suite("Storage/Reagent DTO decoding")
struct StorageDTOsTests {
    private func snakeCaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @Test("decodes the literal StorageObjectSerializer shape, including a null stored_at")
    func decodesStorageObject() throws {
        let json = Data("""
        {
            "id": 1, "object_type": "freezer", "object_name": "Freezer A",
            "object_description": "-80C freezer", "stored_at": null
        }
        """.utf8)
        let dto = try snakeCaseDecoder().decode(StorageObjectDTO.self, from: json)
        #expect(dto.objectName == "Freezer A")
        #expect(dto.storedAt == nil)
    }

    @Test("decodes the literal StoredReagentSerializer shape")
    func decodesStoredReagent() throws {
        let json = Data("""
        {
            "id": 5, "reagent": 2, "reagent_name": "NaCl", "reagent_unit": "g",
            "storage_object": 1, "storage_object_name": "Freezer A",
            "quantity": 100.0, "current_quantity": 87.5,
            "barcode": null, "expiration_date": null, "low_stock_threshold": 10.0
        }
        """.utf8)
        let dto = try snakeCaseDecoder().decode(StoredReagentDTO.self, from: json)
        #expect(dto.reagentName == "NaCl")
        #expect(dto.currentQuantity == 87.5)
        #expect(dto.lowStockThreshold == 10.0)
    }
}
