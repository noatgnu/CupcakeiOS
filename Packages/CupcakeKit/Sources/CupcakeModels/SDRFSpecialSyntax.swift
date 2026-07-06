import Foundation

public enum SDRFSpecialSyntaxType: Equatable, Sendable {
    case age
    case modification
    case cleavage
    case spikedCompound
}

public enum SDRFSyntaxDetector {
    public static func detect(columnName: String, columnType: String) -> SDRFSpecialSyntaxType? {
        for candidate in [columnName, columnType] {
            let lowered = candidate.lowercased()
            if lowered == "characteristics[age]" { return .age }
            if lowered == "comment[modification parameters]" { return .modification }
            if lowered == "comment[cleavage agent details]" { return .cleavage }
            if lowered == "characteristics[spiked compound]" { return .spikedCompound }
        }
        return nil
    }
}

public enum SDRFKeyValueSyntax {
    public static func parse(_ value: String, allowedKeys: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for pair in value.split(separator: ";") {
            guard let equalsIndex = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let fieldValue = String(pair[pair.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            guard allowedKeys.contains(key) else { continue }
            result[key] = fieldValue
        }
        return result
    }

    public static func format(_ fields: [String: String], keyOrder: [String]) -> String {
        keyOrder.compactMap { key -> String? in
            guard let value = fields[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: ";")
    }
}

public enum SDRFModificationKeys {
    public static let order = ["NT", "AC", "CF", "MT", "PP", "TA", "MM", "TS"]
}

public enum SDRFCleavageKeys {
    public static let order = ["NT", "AC", "CS"]
}

public enum SDRFSpikedCompoundKeys {
    public static let order = ["SP", "CT", "QY", "PS", "AC", "CN", "CV", "CS", "CF"]
}

public enum SDRFAgeSyntax {
    public static func parse(_ value: String) -> (years: String, months: String, days: String)? {
        let pattern = /^(\d+)Y(\d+)M(\d+)D$/
        guard let match = try? pattern.wholeMatch(in: value) else { return nil }
        return (String(match.1), String(match.2), String(match.3))
    }

    public static func format(years: String, months: String, days: String) -> String {
        "\(years.isEmpty ? "0" : years)Y\(months.isEmpty ? "0" : months)M\(days.isEmpty ? "0" : days)D"
    }
}
