import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct ColumnTemplateEditSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query private var labGroups: [CachedLabGroup]

    let template: MetadataColumnTemplateDTO?
    let onSaved: () async -> Void

    private static let columnTypes = ["characteristics", "comment", "factor_value", "source_name", "special"]
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
    @State private var columnName: String
    @State private var columnType: String
    @State private var ontologyType: String
    @State private var defaultValue: String
    @State private var defaultPositionText: String
    @State private var visibility: VisibilityOption
    @State private var labGroupServerID: Int64?
    @State private var category: String
    @State private var tagsText: String
    @State private var enableTypeahead: Bool
    @State private var notAvailable: Bool
    @State private var excelValidation: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var ontologySuggestions: [OntologySuggestionDTO] = []
    @State private var ontologySearchTask: Task<Void, Never>?

    init(template: MetadataColumnTemplateDTO?, onSaved: @escaping () async -> Void) {
        self.template = template
        self.onSaved = onSaved
        _name = State(initialValue: template?.name ?? "")
        _description = State(initialValue: template?.description ?? "")
        _columnName = State(initialValue: template?.columnName ?? "")
        _columnType = State(initialValue: template?.columnType ?? "characteristics")
        _ontologyType = State(initialValue: template?.ontologyType ?? "")
        _defaultValue = State(initialValue: template?.defaultValue ?? "")
        _defaultPositionText = State(initialValue: template?.defaultPosition.map(String.init) ?? "")
        _visibility = State(initialValue: VisibilityOption(rawValue: template?.visibility ?? "private") ?? .private)
        _labGroupServerID = State(initialValue: template?.labGroup)
        _category = State(initialValue: template?.category ?? "")
        _tagsText = State(initialValue: (template?.tags ?? []).joined(separator: ", "))
        _enableTypeahead = State(initialValue: template?.enableTypeahead ?? true)
        _notAvailable = State(initialValue: template?.notAvailable ?? false)
        _excelValidation = State(initialValue: template?.excelValidation ?? true)
    }

    private var canSave: Bool {
        !name.isEmpty && !columnName.isEmpty && (visibility != .group || labGroupServerID != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("columnTemplateNameField")
                    TextField("Description", text: $description)
                        .accessibilityIdentifier("columnTemplateDescriptionField")
                    TextField("Category", text: $category)
                    TextField("Tags (comma-separated)", text: $tagsText)
                        .accessibilityIdentifier("columnTemplateTagsField")
                }
                Section("Column") {
                    TextField("Column Name (SDRF)", text: $columnName)
                        .accessibilityIdentifier("columnTemplateColumnNameField")
                    Picker("Type", selection: $columnType) {
                        ForEach(Self.columnTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    TextField("Default Position", text: $defaultPositionText)
                        .accessibilityIdentifier("columnTemplateDefaultPositionField")
                    TextField("Ontology Type", text: $ontologyType)
                        .accessibilityIdentifier("columnTemplateOntologyTypeField")
                    TextField("Default Value", text: $defaultValue)
                        .accessibilityIdentifier("columnTemplateDefaultValueField")
                        .onChange(of: defaultValue) { scheduleOntologySearch() }
                    if !ontologySuggestions.isEmpty {
                        ForEach(ontologySuggestions) { suggestion in
                            Button(suggestion.displayName) {
                                defaultValue = suggestion.value
                                ontologySuggestions = []
                            }
                            .accessibilityIdentifier("columnTemplateOntologySuggestion_\(suggestion.value)")
                        }
                    }
                }
                Section("Options") {
                    Toggle("Enable Typeahead", isOn: $enableTypeahead)
                        .accessibilityIdentifier("columnTemplateEnableTypeaheadToggle")
                    Toggle("Not Available by Default", isOn: $notAvailable)
                        .accessibilityIdentifier("columnTemplateNotAvailableToggle")
                    Toggle("Excel Dropdown Validation", isOn: $excelValidation)
                        .accessibilityIdentifier("columnTemplateExcelValidationToggle")
                }
                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(VisibilityOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .accessibilityIdentifier("columnTemplateVisibilityPicker")
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
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveColumnTemplateButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 480)
        #endif
        .alert("Couldn't save template", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func scheduleOntologySearch() {
        ontologySearchTask?.cancel()
        guard !ontologyType.isEmpty else {
            ontologySuggestions = []
            return
        }
        ontologySearchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, defaultValue.count >= 2 else {
                ontologySuggestions = []
                return
            }
            do {
                let services = appSession.makeSyncServices()
                let found = try await services.metadataColumnSync.fetchOntologySuggestions(ontologyType: ontologyType, customFilters: nil, search: defaultValue)
                guard !Task.isCancelled else { return }
                ontologySuggestions = found
            } catch {
                guard !Task.isCancelled else { return }
                ontologySuggestions = []
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let request = CreateColumnTemplateRequest(
            name: name,
            description: description.isEmpty ? nil : description,
            columnName: columnName,
            columnType: columnType,
            ontologyType: ontologyType.isEmpty ? nil : ontologyType,
            defaultValue: defaultValue.isEmpty ? nil : defaultValue,
            defaultPosition: Int(defaultPositionText),
            visibility: visibility.rawValue,
            labGroup: visibility == .group ? labGroupServerID : nil,
            category: category.isEmpty ? nil : category,
            enableTypeahead: enableTypeahead,
            notAvailable: notAvailable,
            excelValidation: excelValidation,
            tags: tags
        )
        do {
            let services = appSession.makeSyncServices()
            if let template {
                try await services.metadataColumnTemplateSync.update(templateServerID: template.id, request: request)
            } else {
                try await services.metadataColumnTemplateSync.create(request)
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
