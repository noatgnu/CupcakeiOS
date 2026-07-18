import Foundation

extension Date {
    public static func parsedISO8601(_ string: String?, fallback: Date = Date()) -> Date {
        guard let string, let parsed = ISO8601DateFormatter().date(from: string) else {
            return fallback
        }
        return parsed
    }
}
