import CupcakeNetworking
import CupcakeOntology
import CupcakeSync
import SwiftData
import SwiftUI

struct NewMetadataTableTemplateSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let jobLabGroupServerID: Int64?
    let ontologyStore: ModelContainer
    let onCreated: (Int64) -> Void

    private enum StartingPoint: String, CaseIterable, Identifiable {
        case blank = "Blank"
        case fromSchema = "From Schema"
        var id: String { rawValue }
    }

    @State private var startingPoint: StartingPoint = .blank
    @State private var name = ""
    @State private var description = ""
    @State private var useJobLabGroup = false
    @State private var availableSchemas: [CachedSDRFSchema] = []
    @State private var selectedSchemaNames: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var canSave: Bool {
        guard !name.isEmpty else { return false }
        if startingPoint == .fromSchema {
            return !selectedSchemaNames.isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Starting Point") {
                    Picker("Starting Point", selection: $startingPoint) {
                        ForEach(StartingPoint.allCases) { point in
                            Text(point.rawValue).tag(point)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("templateStartingPointPicker")
                }
                Section("Details") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("newTemplateNameField")
                    TextField("Description", text: $description)
                        .accessibilityIdentifier("newTemplateDescriptionField")
                    if jobLabGroupServerID != nil {
                        Toggle("Share with job's lab group", isOn: $useJobLabGroup)
                            .accessibilityIdentifier("newTemplateShareWithLabGroupToggle")
                    }
                }
                if startingPoint == .fromSchema {
                    Section("Schemas") {
                        if availableSchemas.isEmpty {
                            Text("No schemas downloaded yet — import them from Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableSchemas) { schema in
                                Button {
                                    toggleSchema(schema.name)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(schema.displayName ?? schema.name)
                                            if let description = schema.schemaDescription {
                                                Text(description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if selectedSchemaNames.contains(schema.name) {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("schemaRow_\(schema.name)")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("createTemplateButton")
                }
            }
        }
        .frame(minWidth: 380, minHeight: 420)
        .alert("Couldn't create template", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            loadSchemas()
        }
    }

    private func loadSchemas() {
        let context = ModelContext(ontologyStore)
        availableSchemas = (try? context.fetch(FetchDescriptor<CachedSDRFSchema>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    private func toggleSchema(_ name: String) {
        if selectedSchemaNames.contains(name) {
            selectedSchemaNames.remove(name)
        } else {
            selectedSchemaNames.insert(name)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let labGroupServerID = useJobLabGroup ? jobLabGroupServerID : nil
        do {
            let services = appSession.makeSyncServices()
            let template: MetadataTableTemplateDTO
            switch startingPoint {
            case .blank:
                template = try await services.metadataTableTemplateSync.createBlank(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    labGroupServerID: labGroupServerID
                )
            case .fromSchema:
                template = try await services.metadataTableTemplateSync.createFromSchemas(
                    name: name,
                    schemaNames: Array(selectedSchemaNames),
                    description: description.isEmpty ? nil : description,
                    labGroupServerID: labGroupServerID
                )
            }
            onCreated(template.id)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
