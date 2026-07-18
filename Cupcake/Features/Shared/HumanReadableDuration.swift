import Foundation

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
