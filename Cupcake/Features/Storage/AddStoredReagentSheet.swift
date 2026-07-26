import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct AddStoredReagentSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
    @State private var molecularWeightText = ""
    @State private var notes = ""
    @State private var shareable = false
    @State private var accessAll = false
    @State private var notifyOnLowStock = false
    @State private var pngBase64: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    #if os(iOS)
    @State private var isShowingScanner = false
    #endif

    private var canSave: Bool {
        guard !reagentNameQuery.isEmpty, !unit.isEmpty else { return false }
        guard let quantity = Double(quantityText), quantity > 0 else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reagent") {
                    ReagentPickerField(
                        nameQuery: $reagentNameQuery,
                        unit: $unit,
                        matchedReagentID: $matchedReagentID,
                        nameFieldIdentifier: "newStoredReagentNameField",
                        suggestionButtonIdentifier: "newStoredReagentSuggestionButton",
                        unitPickerIdentifier: "newStoredReagentUnitPicker"
                    )
                }
                Section {
                    TextField("Quantity", text: $quantityText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("newStoredReagentQuantityField")
                    TextField("Molecular weight (g/mol, optional)", text: $molecularWeightText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("newStoredReagentMolecularWeightField")
                    HStack {
                        TextField("Barcode", text: $barcode)
                            .accessibilityIdentifier("newStoredReagentBarcodeField")
                        #if os(iOS)
                        if BarcodeScannerAvailability.isSupported {
                            Button {
                                isShowingScanner = true
                            } label: {
                                Image(systemName: "barcode.viewfinder")
                            }
                            .accessibilityIdentifier("scanBarcodeButton")
                            .help("Scan Barcode")
                        }
                        #endif
                    }
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
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("newStoredReagentNotesField")
                }
                Section("Sharing") {
                    Toggle("Notify on low stock", isOn: $notifyOnLowStock)
                        .accessibilityIdentifier("newStoredReagentNotifyToggle")
                    Toggle("Shareable", isOn: $shareable)
                        .accessibilityIdentifier("newStoredReagentShareableToggle")
                    Toggle("Allow everyone to access", isOn: $accessAll)
                        .accessibilityIdentifier("newStoredReagentAccessAllToggle")
                }
                Section("Image") {
                    if let pngBase64, let data = Data(base64Encoded: pngBase64), let image = PlatformImage(data: data) {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                        Button("Remove Photo", role: .destructive) {
                            self.pngBase64 = nil
                        }
                        .accessibilityIdentifier("removeStoredReagentImageButton")
                    } else {
                        StoredReagentPhotoLibraryButton(label: "Choose Photo…") { base64 in
                            pngBase64 = base64
                        }
                        .accessibilityIdentifier("chooseStoredReagentPhotoButton")
                        #if os(iOS)
                        StoredReagentCameraButton(label: "Take Photo…") { base64 in
                            pngBase64 = base64
                        }
                        .accessibilityIdentifier("takeStoredReagentPhotoButton")
                        #endif
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Reagent")
            #if os(iOS)
            .sheet(isPresented: $isShowingScanner) {
                BarcodeScannerView { payload in
                    barcode = payload
                    isShowingScanner = false
                }
                .ignoresSafeArea()
            }
            #endif
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

        let reagent = ReagentPickerField.resolveReagent(
            name: reagentNameQuery,
            unit: unit,
            matchedReagentID: matchedReagentID,
            context: modelContext
        )

        let expirationDateString: String? = hasExpirationDate ? Self.dateFormatter.string(from: expirationDate) : nil
        let lowStockThreshold = Double(lowStockThresholdText)
        let molecularWeight = Double(molecularWeightText)

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
            lowStockThreshold: lowStockThreshold,
            molecularWeight: molecularWeight,
            notes: notes.isEmpty ? nil : notes,
            shareable: shareable,
            accessAll: accessAll,
            notifyOnLowStock: notifyOnLowStock,
            pngBase64: pngBase64
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
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateStoredReagent(clientID: clientID)
            dismiss()
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
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
