import Foundation

/// A single field in a `MolarityHistoryEntry.data` dictionary, round-tripping whichever JSON scalar type was present.
public enum MolarityDataValue: Codable, Sendable, Equatable {
    case number(Double)
    case string(String)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// A single molarity calculation, encoded with plain camelCase keys as opaque JSON in `annotation_text`.
public struct MolarityHistoryEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var data: [String: MolarityDataValue]
    public var operationType: String
    public var result: Double
    public var timestamp: String
    public var calculatedField: String?
    public var scratched: Bool?

    public init(
        id: String = UUID().uuidString,
        data: [String: MolarityDataValue],
        operationType: String,
        result: Double,
        timestamp: String = MolarityHistoryEntry.isoNow(),
        calculatedField: String? = nil,
        scratched: Bool? = nil
    ) {
        self.id = id
        self.data = data
        self.operationType = operationType
        self.result = result
        self.timestamp = timestamp
        self.calculatedField = calculatedField
        self.scratched = scratched
    }

    public static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
