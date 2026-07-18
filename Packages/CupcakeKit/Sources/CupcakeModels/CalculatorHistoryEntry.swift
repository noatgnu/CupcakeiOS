import Foundation

public struct CalculatorHistoryEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var inputPromptFirstValue: Double
    public var inputPromptSecondValue: Double
    public var operation: String
    public var result: Double
    public var timestamp: String
    public var scratched: Bool?

    public init(
        id: String = UUID().uuidString,
        inputPromptFirstValue: Double,
        inputPromptSecondValue: Double = 0,
        operation: String,
        result: Double,
        timestamp: String = CalculatorHistoryEntry.isoNow(),
        scratched: Bool? = nil
    ) {
        self.id = id
        self.inputPromptFirstValue = inputPromptFirstValue
        self.inputPromptSecondValue = inputPromptSecondValue
        self.operation = operation
        self.result = result
        self.timestamp = timestamp
        self.scratched = scratched
    }

    public static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
