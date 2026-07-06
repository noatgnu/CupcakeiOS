import Foundation

/// Step/section durations are stored in seconds and can be large (a "2160 min" overnight
/// incubation step) — breaking into days/hours/minutes reads naturally where a raw minute count
/// doesn't.
enum HumanReadableDuration {
    static func format(seconds: Int) -> String {
        formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }

    private static let formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
}
