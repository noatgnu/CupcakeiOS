import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Field set and reagent-typeahead pattern verified against the reference web app's
/// `stored-reagent-create-modal.ts` (fields 28-39, html 22-239): reagent name (typeahead against
/// the existing catalog, creating a new `Reagent` inline on save if the typed name doesn't
/// match), quantity + unit (unit only matters for a brand-new reagent), barcode, expiration
/// date, low stock threshold. `molecularWeight`/`notes`/`shareable`/`accessAll`/image upload
/// exist in the reference modal too but are deliberately out of scope here — this app's
/// `CachedStoredReagent` model doesn't carry them yet, and adding all five is unrelated scope
/// creep for what this sheet needs to do (create a stock entry offline).
///
/// Always created locally first, then synced immediately when signed in — a genuine
/// unreachability failure queues it in the outbox, same pattern as every other create flow.
struct AddStoredReagentSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CachedReagent.name) private var reagents: [CachedReagent]

    let storageObjectServerID: Int64
    let storageObjectName: String

    @State private var reagentNameQuery = ""
    @State private var matchedReagentID: UUID?
    @State private var unit = ""
    @State private var quantityText = ""
    @State private var barcode = ""
    @State private var expirationDate = Date()
    @State private var hasExpirationDate = false
    @State private var lowStockThresholdText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private static let unitOptions = ["nL", "uL", "mL", "L", "ng", "ug", "mg", "g", "kg", "nM", "uM", "mM", "M", "ea", "pieces", "other"]

    private var suggestions: [CachedReagent] {
        guard !reagentNameQuery.isEmpty, matchedReagentID == nil else { return [] }
        return reagents.filter { $0.name.localizedCaseInsensitiveContains(reagentNameQuery) }.prefix(10).map { $0 }
    }

    private var canSave: Bool {
        guard !reagentNameQuery.isEmpty, !unit.isEmpty else { return false }
        guard let quantity = Double(quantityText), quantity > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reagent") {
                    TextField("Reagent name", text: $reagentNameQuery)
                        .accessibilityIdentifier("newStoredReagentNameField")
                        .onChange(of: reagentNameQuery) { matchedReagentID = nil }
                    ForEach(suggestions) { reagent in
                        Button {
                            reagentNameQuery = reagent.name
                            unit = reagent.unit
                            matchedReagentID = reagent.clientID
                        } label: {
                            Text("\(reagent.name) (\(reagent.unit))")
                        }
                        .accessibilityIdentifier("newStoredReagentSuggestionButton")
                    }
                    Picker("Unit", selection: $unit) {
                        Text("Select…").tag("")
                        ForEach(Self.unitOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .accessibilityIdentifier("newStoredReagentUnitPicker")
                }
                Section {
                    TextField("Quantity", text: $quantityText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("newStoredReagentQuantityField")
                    TextField("Barcode", text: $barcode)
                        .accessibilityIdentifier("newStoredReagentBarcodeField")
                    Toggle("Has expiration date", isOn: $hasExpirationDate)
                        .accessibilityIdentifier("newStoredReagentHasExpirationToggle")
                    if hasExpirationDate {
                        DatePicker("Expiration date", selection: $expirationDate, displayedComponents: .date)
                    }
                    TextField("Low stock threshold (optional)", text: $lowStockThresholdText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("newStoredReagentLowStockField")
                } header: {
                    Text("Stock")
                } footer: {
                    Text("Stored at \(storageObjectName).")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Reagent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveStoredReagentButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 460)
        .alert("Couldn't add reagent", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let quantity = Double(quantityText) else { return }
        isSaving = true
        defer { isSaving = false }

        let reagent: CachedReagent
        if let matchedReagentID, let matched = reagents.first(where: { $0.clientID == matchedReagentID }) {
            reagent = matched
        } else {
            let created = CachedReagent(name: reagentNameQuery, unit: unit)
            modelContext.insert(created)
            reagent = created
        }

        let expirationDateString: String? = hasExpirationDate ? Self.dateFormatter.string(from: expirationDate) : nil
        let lowStockThreshold = Double(lowStockThresholdText)

        let storedReagent = CachedStoredReagent(
            reagentServerID: reagent.serverID,
            reagentClientID: reagent.clientID,
            reagentName: reagentNameQuery,
            reagentUnit: unit,
            storageObjectServerID: storageObjectServerID,
            storageObjectName: storageObjectName,
            quantity: quantity,
            currentQuantity: quantity,
            barcode: barcode.isEmpty ? nil : barcode,
            expirationDate: expirationDateString,
            lowStockThreshold: lowStockThreshold
        )
        modelContext.insert(storedReagent)
        try? modelContext.save()

        guard appSession.isAuthenticated else {
            dismiss()
            return
        }

        let clientID = storedReagent.clientID
        let services = appSession.makeSyncServices()
        do {
            try await services.inventorySync.syncLocallyCreatedStoredReagent(clientID: clientID)
            dismiss()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateStoredReagent(clientID: clientID)
                dismiss()
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateStoredReagent(clientID: clientID)
            dismiss()
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
            isShowingError = true
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
