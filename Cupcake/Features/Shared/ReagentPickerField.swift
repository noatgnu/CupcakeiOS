import CupcakeModels
import SwiftData
import SwiftUI

struct ReagentPickerField: View {
    @Query(sort: \CachedReagent.createdAt, order: .reverse) private var reagents: [CachedReagent]

    @Binding var nameQuery: String
    @Binding var unit: String
    @Binding var matchedReagentID: UUID?

    var nameFieldIdentifier = "reagentNameField"
    var suggestionButtonIdentifier = "reagentSuggestionButton"
    var unitPickerIdentifier = "reagentUnitPicker"

    static let unitOptions = ["nL", "uL", "mL", "L", "ng", "ug", "mg", "g", "kg", "nM", "uM", "mM", "M", "ea", "pieces", "other"]

    private var suggestions: [CachedReagent] {
        guard !nameQuery.isEmpty, matchedReagentID == nil else { return [] }
        return reagents.filter { $0.name.localizedCaseInsensitiveContains(nameQuery) }.prefix(10).map { $0 }
    }

    var body: some View {
        TextField("Reagent name", text: $nameQuery)
            .accessibilityIdentifier(nameFieldIdentifier)
            .onChange(of: nameQuery) { matchedReagentID = nil }
        ForEach(suggestions) { reagent in
            Button {
                nameQuery = reagent.name
                unit = reagent.unit
                matchedReagentID = reagent.clientID
            } label: {
                Text("\(reagent.name) (\(reagent.unit))")
            }
            .accessibilityIdentifier(suggestionButtonIdentifier)
        }
        Picker("Unit", selection: $unit) {
            Text("Select…").tag("")
            ForEach(Self.unitOptions, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .accessibilityIdentifier(unitPickerIdentifier)
    }

    static func resolveReagent(
        name: String,
        unit: String,
        matchedReagentID: UUID?,
        context: ModelContext
    ) -> CachedReagent {
        let all = (try? context.fetch(FetchDescriptor<CachedReagent>())) ?? []
        if let matchedReagentID, let matched = all.first(where: { $0.clientID == matchedReagentID }) {
            return matched
        }
        if let exact = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.unit == unit }) {
            return exact
        }
        let created = CachedReagent(name: name, unit: unit)
        context.insert(created)
        return created
    }
}
