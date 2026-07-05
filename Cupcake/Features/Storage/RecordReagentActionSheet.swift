import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// `actionType` is exactly `"add"`/`"reserve"` — confirmed against `ccm/models.py:700-703`'s
/// `action_type_choices`; there is no `"consume"` choice anywhere in the backend, despite that
/// being an intuitive-seeming third option. `quantity` must be positive regardless of
/// `actionType` — the add/subtract sign comes from `actionType`, not the sign of `quantity`.
///
/// Always recorded locally first (updating `currentQuantity` immediately so the UI reflects it
/// without waiting on a round-trip), then synced right away when signed in — a genuine
/// unreachability failure queues it in the outbox, same pattern as every other create flow.
struct RecordReagentActionSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let storedReagent: CachedStoredReagent

    @State private var actionType = "add"
    @State private var quantityText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var canSave: Bool {
        guard let quantity = Double(quantityText), quantity > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Action", selection: $actionType) {
                        Text("Add").tag("add")
                        Text("Reserve").tag("reserve")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("reagentActionTypePicker")
                    TextField("Quantity", text: $quantityText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("reagentActionQuantityField")
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .accessibilityIdentifier("reagentActionNotesField")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Record Action")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveReagentActionButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 280)
        .alert("Couldn't record action", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let quantity = Double(quantityText) else { return }
        isSaving = true
        defer { isSaving = false }

        let action = CachedReagentAction(
            storedReagentClientID: storedReagent.clientID,
            actionType: actionType,
            quantity: quantity,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(action)
        // Optimistic local update — the server computes `current_quantity` as a sum of actions,
        // but the UI shouldn't have to wait on a round-trip to reflect a just-recorded action.
        storedReagent.currentQuantity += actionType == "add" ? quantity : -quantity
        try? modelContext.save()

        guard appSession.isAuthenticated else {
            dismiss()
            return
        }

        let clientID = action.clientID
        let services = appSession.makeSyncServices()
        do {
            try await services.inventorySync.syncLocallyCreatedReagentAction(clientID: clientID)
            dismiss()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateReagentAction(clientID: clientID)
                dismiss()
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateReagentAction(clientID: clientID)
            dismiss()
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
            isShowingError = true
        }
    }
}
