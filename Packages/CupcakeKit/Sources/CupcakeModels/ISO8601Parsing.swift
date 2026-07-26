import Foundation

extension Date {
    public static func parsedISO8601(_ string: String?, fallback: Date = Date()) -> Date {
        guard let string else { return fallback }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractionalFormatter.date(from: string) {
            return parsed
        }
        if let parsed = ISO8601DateFormatter().date(from: string) {
            return parsed
        }
        return fallback
    }
}
