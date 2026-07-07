import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct TableTemplateEditSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query private var labGroups: [CachedLabGroup]

    let template: MetadataTableTemplateDTO
    let onSaved: () async -> Void

    private enum VisibilityOption: String, CaseIterable, Identifiable {
        case `private`
        case group
        case `public`
        var id: String { rawValue }
        var label: String {
            switch self {
            case .private: return "Private"
            case .group: return "Lab Group"
            case .public: return "Public"
            }
        }
    }

    @State private var name: String
    @State private var description: String
    @State private var visibility: VisibilityOption
    @State private var labGroupServerID: Int64?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(template: MetadataTableTemplateDTO, onSaved: @escaping () async -> Void) {
        self.template = template
        self.onSaved = onSaved
        _name = State(initialValue: template.name)
        _description = State(initialValue: template.description ?? "")
        _visibility = State(initialValue: VisibilityOption(rawValue: template.visibility) ?? .private)
        _labGroupServerID = State(initialValue: template.labGroup)
    }

    private var canSave: Bool {
        !name.isEmpty && (visibility != .group || labGroupServerID != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("tableTemplateNameField")
                    TextField("Description", text: $description)
                        .accessibilityIdentifier("tableTemplateDescriptionField")
                }
                if !template.schemaNames.isEmpty {
                    Section("Created From") {
                        ForEach(template.schemaNames, id: \.self) { schemaName in
                            Text(schemaName)
                        }
                    }
                }
                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(VisibilityOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .accessibilityIdentifier("tableTemplateVisibilityPicker")
                    if visibility == .group {
                        Picker("Lab Group", selection: $labGroupServerID) {
                            Text("None").tag(Int64?.none)
                            ForEach(labGroups) { labGroup in
                                Text(labGroup.name).tag(Optional(labGroup.serverID))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveTableTemplateButton")
                }
            }
        }
        .frame(minWidth: 380, minHeight: 420)
        .alert("Couldn't save template", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let request = CreateMetadataTableTemplateRequest(
            name: name,
            description: description.isEmpty ? nil : description,
            labGroup: visibility == .group ? labGroupServerID : nil,
            visibility: visibility.rawValue
        )
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataTableTemplateSync.update(templateServerID: template.id, request: request)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
