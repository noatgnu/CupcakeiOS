import Foundation

public enum UnimodAdditionalDataParser {
    public struct ParsedData {
        public let deltaMonoMass: String?
        public let deltaAvgeMass: String?
        public let deltaComposition: String?
        public let specifications: [String: [String: String]]
    }

    private struct RawEntry: Decodable {
        let id: String
        let description: String
    }

    public static func parse(_ additionalData: String?) -> ParsedData {
        guard let additionalData, let data = additionalData.data(using: .utf8),
              let entries = try? JSONDecoder().decode([RawEntry].self, from: data) else {
            return ParsedData(deltaMonoMass: nil, deltaAvgeMass: nil, deltaComposition: nil, specifications: [:])
        }

        var flat: [String: String] = [:]
        for entry in entries {
            flat[entry.id] = entry.description
        }

        var specifications: [String: [String: String]] = [:]
        let specPrefix = "spec_"
        for (key, value) in flat where key.hasPrefix(specPrefix) {
            let remainder = key.dropFirst(specPrefix.count)
            guard let underscoreIndex = remainder.firstIndex(of: "_") else { continue }
            let indexString = String(remainder[remainder.startIndex..<underscoreIndex])
            let field = String(remainder[remainder.index(after: underscoreIndex)...])
            specifications[indexString, default: [:]][field] = value
        }

        return ParsedData(
            deltaMonoMass: flat["delta_mono_mass"],
            deltaAvgeMass: flat["delta_avge_mass"],
            deltaComposition: flat["delta_composition"],
            specifications: specifications
        )
    }
}
