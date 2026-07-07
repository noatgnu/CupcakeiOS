import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Edits an already-attached step-reagent's quantity/scaling.
struct EditStepReagentSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let stepReagent: CachedStepReagent

    @State private var quantityText: String
    @State private var isScalable: Bool
    @State private var scalableFactorText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(stepReagent: CachedStepReagent) {
        self.stepReagent = stepReagent
        _quantityText = State(initialValue: String(stepReagent.quantity))
        _isScalable = State(initialValue: stepReagent.scalable)
        _scalableFactorText = State(initialValue: String(stepReagent.scalableFactor))
    }

    private var canSave: Bool {
        guard let quantity = Double(quantityText), quantity > 0 else { return false }
        if isScalable, Double(scalableFactorText) == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Quantity", text: $quantityText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .accessibilityIdentifier("editReagentQuantityField")
                Toggle("Scalable", isOn: $isScalable)
                    .accessibilityIdentifier("editReagentScalableToggle")
                if isScalable {
                    TextField("Scale Factor", text: $scalableFactorText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("editReagentScalableFactorField")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Reagent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveEditReagentButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 260)
        .alert("Couldn't save reagent", isPresented: $isShowingError) {
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

        stepReagent.quantity = quantity
        stepReagent.scalable = isScalable
        stepReagent.scalableFactor = scalableFactor
        try? modelContext.save()

        guard let serverID = stepReagent.serverID else {
            dismiss()
            return
        }
        do {
            try await appSession.makeSyncServices().stepReagentSync.update(serverID: serverID, quantity: quantity, scalable: isScalable, scalableFactor: scalableFactor)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
