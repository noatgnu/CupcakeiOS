import Foundation

nonisolated enum HumanReadableTime {
    static func format(_ isoString: String?) -> String? {
        guard let isoString, let date = parseISO8601(isoString) else { return isoString }
        let hoursAgo = abs(date.timeIntervalSinceNow) / 3600
        if hoursAgo < 24 * 7 {
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func formatAbsolute(_ isoString: String?) -> String? {
        guard let isoString, let date = parseISO8601(isoString) else { return isoString }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    static func formatRange(start: String?, end: String?) -> String {
        let startText = formatAbsolute(start) ?? "Unknown start"
        guard let endText = formatAbsolute(end) else { return "\(startText) – In progress" }
        return "\(startText) – \(endText)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
