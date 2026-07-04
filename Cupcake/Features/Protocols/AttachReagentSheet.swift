import CupcakeModels
import CupcakeSync
import SwiftData
import SwiftUI

/// Completes the Protocol -> Section -> Step -> StepReagent authoring hierarchy: attaching a
/// reagent (existing or newly named on the spot) with a quantity to a step. Creates on the
/// server when the owning protocol is online-authored (`canAuthorOnline`), falling back to a
/// local-only write otherwise — same "online when possible, else local" pattern used for
/// session/protocol/section/step creation.
///
/// Verified against the reference web app's `step-reagent-modal.ts`:
/// - Reagent name is a live typeahead (`searchReagent()`, 200ms debounce, min 1 char) against the
///   real reagent catalog, not a plain picker — this app searches its local `CachedReagent` cache
///   instead of a network call, consistent with everything else in this offline-authoring flow.
///   Selecting a suggestion autofills both name and unit (`onSelectReagent()`).
/// - Unit is a fixed-list dropdown (`step-reagent-modal.html:41-73`), not free text.
/// - `quantity`, `scalable`, `scalableFactor` are all real, independently editable fields there
///   (not a quantity-only form) — `scalableFactor` is forced back to `1` whenever `scalable` is
///   off.
struct AttachReagentSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CachedReagent.name) private var reagents: [CachedReagent]

    let step: CachedProtocolStep
    let canAuthorOnline: Bool

    /// Exact list from `step-reagent-modal.html`'s `<select>` — Volume, Mass, Mole, Count, Other.
    private static let unitOptions = ["nL", "uL", "mL", "L", "ng", "ug", "mg", "g", "kg", "nM", "uM", "mM", "M", "ea", "pieces", "other"]

    @State private var reagentNameQuery = ""
    @State private var matchedReagentID: UUID?
    @State private var unit = ""
    @State private var quantityText = ""
    @State private var isScalable = false
    @State private var scalableFactorText = "1"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var suggestions: [CachedReagent] {
        guard !reagentNameQuery.isEmpty, matchedReagentID == nil else { return [] }
        return reagents.filter { $0.name.localizedCaseInsensitiveContains(reagentNameQuery) }.prefix(10).map { $0 }
    }

    private var canSave: Bool {
        guard !reagentNameQuery.isEmpty, !unit.isEmpty else { return false }
        guard let quantity = Double(quantityText), quantity > 0 else { return false }
        if isScalable, Double(scalableFactorText) == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reagent") {
                    TextField("Reagent name", text: $reagentNameQuery)
                        .accessibilityIdentifier("reagentNameField")
                        .onChange(of: reagentNameQuery) { matchedReagentID = nil }
                    ForEach(suggestions) { reagent in
                        Button {
                            reagentNameQuery = reagent.name
                            unit = reagent.unit
                            matchedReagentID = reagent.clientID
                        } label: {
                            Text("\(reagent.name) (\(reagent.unit))")
                        }
                        .accessibilityIdentifier("reagentSuggestionButton")
                    }
                    Picker("Unit", selection: $unit) {
                        Text("Select…").tag("")
                        ForEach(Self.unitOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .accessibilityIdentifier("reagentUnitPicker")
                }
                Section {
                    TextField("Quantity", text: $quantityText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("reagentQuantityField")
                    Toggle("Scalable", isOn: $isScalable)
                        .accessibilityIdentifier("reagentScalableToggle")
                    if isScalable {
                        TextField("Scale Factor", text: $scalableFactorText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .accessibilityIdentifier("reagentScalableFactorField")
                    }
                } header: {
                    Text("Quantity")
                } footer: {
                    Text("Scalable reagents scale their quantity by this factor when a session's sample/replicate count changes.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Attach Reagent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveReagentButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .alert("Couldn't attach reagent", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let quantity = Double(quantityText) else { return }
        let scalableFactor = isScalable ? (Double(scalableFactorText) ?? 1.0) : 1.0
        isSaving = true
        defer { isSaving = false }

        if canAuthorOnline, let stepServerID = step.serverID {
            do {
                let services = appSession.makeSyncServices()
                let reagentServerID: Int64
                if let matchedReagentID, let matched = reagents.first(where: { $0.clientID == matchedReagentID }), let existingServerID = matched.serverID {
                    reagentServerID = existingServerID
                } else {
                    let created = try await services.stepReagentSync.createReagent(name: reagentNameQuery, unit: unit)
                    reagentServerID = created.serverID
                }
                try await services.stepReagentSync.createStepReagent(
                    stepServerID: stepServerID,
                    reagentServerID: reagentServerID,
                    quantity: quantity,
                    scalable: isScalable,
                    scalableFactor: scalableFactor
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        } else {
            let reagentClientID: UUID
            if let matchedReagentID {
                reagentClientID = matchedReagentID
            } else {
                let reagent = CachedReagent(name: reagentNameQuery, unit: unit)
                modelContext.insert(reagent)
                reagentClientID = reagent.clientID
            }

            let stepReagent = CachedStepReagent(
                stepClientID: step.clientID,
                reagentClientID: reagentClientID,
                quantity: quantity,
                scalable: isScalable,
                scalableFactor: scalableFactor
            )
            modelContext.insert(stepReagent)
            try? modelContext.save()
            dismiss()
        }
    }
}
