import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct MetadataColumnSettingsSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let column: MetadataColumnDTO
    let onSaved: (MetadataColumnDTO) async -> Void

    private static let columnTypes = ["characteristics", "comment", "factor_value", "source_name", "special"]

    @State private var name: String
    @State private var type: String
    @State private var ontologyType: String
    @State private var mandatory: Bool
    @State private var hidden: Bool
    @State private var readonly: Bool
    @State private var staffOnly: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(column: MetadataColumnDTO, onSaved: @escaping (MetadataColumnDTO) async -> Void) {
        self.column = column
        self.onSaved = onSaved
        _name = State(initialValue: column.name)
        _type = State(initialValue: column.type)
        _ontologyType = State(initialValue: column.ontologyType ?? "")
        _mandatory = State(initialValue: column.mandatory)
        _hidden = State(initialValue: column.hidden)
        _readonly = State(initialValue: column.readonly)
        _staffOnly = State(initialValue: column.staffOnly)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Column") {
                    TextField("Name (SDRF)", text: $name)
                        .accessibilityIdentifier("columnSettingsNameField")
                    Picker("Type", selection: $type) {
                        ForEach(Self.columnTypes, id: \.self) { columnType in
                            Text(columnType).tag(columnType)
                        }
                    }
                    TextField("Ontology Type", text: $ontologyType)
                        .accessibilityIdentifier("columnSettingsOntologyTypeField")
                }
                Section("Flags") {
                    Toggle("Mandatory", isOn: $mandatory)
                        .accessibilityIdentifier("columnSettingsMandatoryToggle")
                    Toggle("Hidden", isOn: $hidden)
                        .accessibilityIdentifier("columnSettingsHiddenToggle")
                    Toggle("Read Only", isOn: $readonly)
                        .accessibilityIdentifier("columnSettingsReadonlyToggle")
                    Toggle("Staff Only", isOn: $staffOnly)
                        .accessibilityIdentifier("columnSettingsStaffOnlyToggle")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Column Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || isSaving)
                    .accessibilityIdentifier("saveColumnSettingsButton")
                }
            }
        }
        .frame(minWidth: 380, minHeight: 420)
        .alert("Couldn't save column", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let request = UpdateMetadataColumnRequest(
            name: name,
            type: type,
            mandatory: mandatory,
            hidden: hidden,
            readonly: readonly,
            staffOnly: staffOnly,
            ontologyType: ontologyType.isEmpty ? nil : ontologyType
        )
        do {
            let services = appSession.makeSyncServices()
            let updated = try await services.metadataColumnSync.updateColumn(columnServerID: column.id, request: request)
            await onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
