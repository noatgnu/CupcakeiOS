import Foundation

/// Every timestamp synced from the server is a raw ISO8601 string — displaying it as-is (e.g.
/// "2026-07-05T21:42:00Z") isn't natural to read. Relative phrasing ("2 hours ago") for anything
/// recent, falling back to an abbreviated absolute date/time further out, matches how most
/// system apps (Messages, Mail) present timestamps.
enum HumanReadableTime {
    static func format(_ isoString: String?) -> String? {
        guard let isoString, let date = ISO8601DateFormatter().date(from: isoString) else { return isoString }
        let hoursAgo = abs(date.timeIntervalSinceNow) / 3600
        if hoursAgo < 24 * 7 {
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Always abbreviated absolute date/time, never relative — for start–end range displays
    /// (a booking's "2 hours ago – 3 days ago" reads oddly; consistent absolute dates don't).
    static func formatAbsolute(_ isoString: String?) -> String? {
        guard let isoString, let date = ISO8601DateFormatter().date(from: isoString) else { return isoString }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
