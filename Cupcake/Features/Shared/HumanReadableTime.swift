import Foundation

/// Formats a raw ISO8601 timestamp as relative phrasing for recent dates, absolute further out.
enum HumanReadableTime {
    static func format(_ isoString: String?) -> String? {
        guard let isoString, let date = ISO8601DateFormatter().date(from: isoString) else { return isoString }
        let hoursAgo = abs(date.timeIntervalSinceNow) / 3600
        if hoursAgo < 24 * 7 {
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Always an abbreviated absolute date/time, never relative.
    static func formatAbsolute(_ isoString: String?) -> String? {
        guard let isoString, let date = ISO8601DateFormatter().date(from: isoString) else { return isoString }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// A start–end pair as one absolute-date range, falling back to "In progress" with no end.
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
