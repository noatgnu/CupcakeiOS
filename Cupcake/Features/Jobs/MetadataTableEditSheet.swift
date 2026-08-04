import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct MetadataTableEditSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query private var labGroups: [CachedLabGroup]

    let table: MetadataTableDTO
    let onSaved: () async -> Void

    @State private var name: String
    @State private var description: String
    @State private var sampleCountText: String
    @State private var labGroupServerID: Int64?
    @State private var isPublished: Bool
    @State private var isLocked: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var pendingConfirmationMessage: String?
    @State private var isShowingSampleCountConfirmation = false

    init(table: MetadataTableDTO, onSaved: @escaping () async -> Void) {
        self.table = table
        self.onSaved = onSaved
        _name = State(initialValue: table.name)
        _description = State(initialValue: table.description ?? "")
        _sampleCountText = State(initialValue: String(table.sampleCount))
        _labGroupServerID = State(initialValue: table.labGroup)
        _isPublished = State(initialValue: table.isPublished)
        _isLocked = State(initialValue: table.isLocked)
    }

    private var canSave: Bool {
        !name.isEmpty && Int(sampleCountText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("metadataTableEditNameField")
                    TextField("Description", text: $description)
                        .accessibilityIdentifier("metadataTableEditDescriptionField")
                    TextField("Sample Count", text: $sampleCountText)
                        .accessibilityIdentifier("metadataTableEditSampleCountField")
                }
                Section("Lab Group") {
                    Picker("Lab Group", selection: $labGroupServerID) {
                        Text("None").tag(Int64?.none)
                        ForEach(labGroups) { labGroup in
                            Text(labGroup.name).tag(Optional(labGroup.serverID))
                        }
                    }
                }
                Section("Status") {
                    Toggle("Published", isOn: $isPublished)
                        .accessibilityIdentifier("metadataTableEditPublishedToggle")
                    Toggle("Locked", isOn: $isLocked)
                        .accessibilityIdentifier("metadataTableEditLockedToggle")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Metadata Table")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save(confirmed: false) }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveMetadataTableEditButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 460)
        #endif
        .alert("Couldn't save table", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Reduce Sample Count?", isPresented: $isShowingSampleCountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reduce Anyway", role: .destructive) {
                Task { await save(confirmed: true) }
            }
            .accessibilityIdentifier("confirmSampleCountReductionButton")
        } message: {
            Text(pendingConfirmationMessage ?? "")
        }
    }

    private func save(confirmed: Bool) async {
        guard let sampleCount = Int(sampleCountText) else { return }
        isSaving = true
        defer { isSaving = false }
        let request = UpdateMetadataTableRequest(
            name: name,
            description: description.isEmpty ? nil : description,
            sampleCount: sampleCount,
            sampleCountConfirmed: confirmed ? true : nil,
            labGroup: labGroupServerID,
            isPublished: isPublished,
            isLocked: isLocked
        )
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataTableSync.update(tableServerID: table.id, request: request)
            await onSaved()
            dismiss()
        } catch let error as APIError {
            if !confirmed, case let .http(status, body) = error, status == 400,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               json["sample_count_confirmation_details"] != nil {
                pendingConfirmationMessage = error.userFacingMessage
                isShowingSampleCountConfirmation = true
            } else {
                errorMessage = error.userFacingMessage
                isShowingError = true
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
