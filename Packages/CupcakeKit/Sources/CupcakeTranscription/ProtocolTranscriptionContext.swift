import CupcakeModels
import Foundation

public enum ProtocolTranscriptionContext {
    private static let maxAdditionalContextCharacters = 150

    public static func vocabulary(
        protocols: [CachedProtocol],
        stepReagents: [CachedStepReagent],
        reagents: [CachedReagent],
        additionalContextText: String? = nil
    ) -> [String] {
        let stepClientIDs = Set(protocols.flatMap { $0.sections.flatMap { $0.steps.map(\.clientID) } })
        let reagentClientIDs = Set(
            stepReagents
                .filter { stepClientIDs.contains($0.stepClientID) }
                .map(\.reagentClientID)
        )
        let reagentNames = reagents
            .filter { reagentClientIDs.contains($0.clientID) }
            .map(\.name)

        var terms: [String] = []
        for protocolModel in protocols {
            terms.append(protocolModel.protocolTitle)
            for section in protocolModel.sections {
                if let description = section.sectionDescription {
                    terms.append(description)
                }
            }
        }
        terms.append(contentsOf: reagentNames)
        if let additionalContextText {
            terms.append(String(additionalContextText.prefix(maxAdditionalContextCharacters)))
        }
        return deduplicated(terms)
    }

    private static func deduplicated(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }
}
