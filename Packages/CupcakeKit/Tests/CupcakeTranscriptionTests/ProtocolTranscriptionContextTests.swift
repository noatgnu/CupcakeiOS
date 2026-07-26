import CupcakeModels
import Foundation
import Testing

@testable import CupcakeTranscription

@Suite("ProtocolTranscriptionContext")
struct ProtocolTranscriptionContextTests {
    @Test("vocabulary includes the protocol title, section descriptions, and only reagents attached within the given protocols, deduplicated")
    func vocabularyCombinesProtocolContentAndScopedReagents() {
        let protocolModel = CachedProtocol(serverID: 1, protocolTitle: "Expression and purification of Rab10 (1-181)", enabled: true)
        let section = CachedProtocolSection(serverID: 1, sectionDescription: "Preparation of cell lysate and pulldown of His-Rab10 on Ni-agarose", order: 0, protocolModel: protocolModel)
        let step = CachedProtocolStep(serverID: 1, stepDescription: "<p>Add Ni-agarose.</p>", order: 0, section: section)
        section.steps = [step]
        protocolModel.sections = [section]

        let reagent = CachedReagent(serverID: 1, name: "Ni-agarose resin", unit: "mL")
        let otherProtocolReagent = CachedReagent(serverID: 2, name: "Unrelated Reagent", unit: "mL")
        let stepReagent = CachedStepReagent(serverID: 1, stepClientID: step.clientID, reagentClientID: reagent.clientID, quantity: 3, scalable: false, scalableFactor: 1)
        let unrelatedStepReagent = CachedStepReagent(serverID: 2, stepClientID: UUID(), reagentClientID: otherProtocolReagent.clientID, quantity: 1, scalable: false, scalableFactor: 1)

        let vocabulary = ProtocolTranscriptionContext.vocabulary(
            protocols: [protocolModel],
            stepReagents: [stepReagent, unrelatedStepReagent],
            reagents: [reagent, otherProtocolReagent],
            additionalContextText: "Add Ni-agarose."
        )

        #expect(vocabulary.contains("Expression and purification of Rab10 (1-181)"))
        #expect(vocabulary.contains("Preparation of cell lysate and pulldown of His-Rab10 on Ni-agarose"))
        #expect(vocabulary.contains("Ni-agarose resin"))
        #expect(!vocabulary.contains("Unrelated Reagent"))
        #expect(vocabulary.filter { $0 == "Expression and purification of Rab10 (1-181)" }.count == 1)
    }

    @Test("vocabulary skips empty/whitespace-only terms and never crashes on an empty protocol list")
    func vocabularyHandlesEmptyInput() {
        let vocabulary = ProtocolTranscriptionContext.vocabulary(protocols: [], stepReagents: [], reagents: [])
        #expect(vocabulary.isEmpty)
    }

    @Test("vocabulary truncates a long additionalContextText rather than injecting an entire step description as prompt content")
    func vocabularyTruncatesLongAdditionalContext() {
        let longText = String(repeating: "This step involves many detailed instructions. ", count: 20)
        let vocabulary = ProtocolTranscriptionContext.vocabulary(
            protocols: [],
            stepReagents: [],
            reagents: [],
            additionalContextText: longText
        )
        #expect(vocabulary.count == 1)
        #expect(vocabulary[0].count <= 150)
        #expect(longText.count > 150)
    }
}
