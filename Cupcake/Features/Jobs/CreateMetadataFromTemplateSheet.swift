import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct CreateMetadataFromTemplateSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \CachedMetadataTableTemplate.name) private var templates: [CachedMetadataTableTemplate]

    let jobClientID: UUID
    let jobServerID: Int64
    let jobLabGroupServerID: Int64?
    let defaultSampleCount: Int?
    let ontologyStore: ModelContainer

    @State private var selectedTemplateID: Int64?
    @State private var sampleCountText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingNewTemplateSheet = false
    @State private var isShowingManagementSheet = false
    @State private var searchText = ""

    init(jobClientID: UUID, jobServerID: Int64, jobLabGroupServerID: Int64?, defaultSampleCount: Int?, ontologyStore: ModelContainer) {
        self.jobClientID = jobClientID
        self.jobServerID = jobServerID
        self.jobLabGroupServerID = jobLabGroupServerID
        self.defaultSampleCount = defaultSampleCount
        self.ontologyStore = ontologyStore
        _sampleCountText = State(initialValue: defaultSampleCount.map(String.init) ?? "")
    }

    private var canSave: Bool {
        selectedTemplateID != nil
    }

    private var searchedTemplates: [CachedMetadataTableTemplate] {
        guard !searchText.isEmpty else { return templates }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var personalTemplates: [CachedMetadataTableTemplate] {
        searchedTemplates.filter { $0.visibility == "private" }
    }

    private var jobLabGroupTemplates: [CachedMetadataTableTemplate] {
        guard let jobLabGroupServerID else { return [] }
        return searchedTemplates.filter { $0.visibility == "group" && $0.labGroupServerID == jobLabGroupServerID }
    }

    private var otherLabGroupTemplates: [CachedMetadataTableTemplate] {
        searchedTemplates.filter { $0.visibility == "group" && $0.labGroupServerID != jobLabGroupServerID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !templates.isEmpty {
                    TextField("Search templates", text: $searchText)
                        .accessibilityIdentifier("templateSearchField")
                }
                if templates.isEmpty {
                    Text("No metadata table templates available.")
                        .foregroundStyle(.secondary)
                } else if searchedTemplates.isEmpty {
                    Text("No templates match \"\(searchText)\".")
                        .foregroundStyle(.secondary)
                } else {
                    templateSection("Personal", templates: personalTemplates)
                    templateSection("Job's Lab Group", templates: jobLabGroupTemplates)
                    templateSection("Other Lab Groups", templates: otherLabGroupTemplates)
                }
                Section {
                    Button("New Template…") {
                        isShowingNewTemplateSheet = true
                    }
                    .accessibilityIdentifier("newMetadataTableTemplateButton")
                    Button("Manage Templates…") {
                        if PlatformWindowPreference.prefersSeparateWindow {
                            openWindow(id: "table-template-manager")
                        } else {
                            isShowingManagementSheet = true
                        }
                    }
                    .accessibilityIdentifier("manageMetadataTableTemplatesButton")
                }
                Section("Sample Count") {
                    TextField("Sample count", text: $sampleCountText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityIdentifier("metadataSampleCountField")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Create Metadata Table")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("createMetadataTableButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 400)
        .alert("Couldn't create metadata table", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingNewTemplateSheet) {
            NewMetadataTableTemplateSheet(jobLabGroupServerID: jobLabGroupServerID, ontologyStore: ontologyStore) { newTemplateServerID in
                selectedTemplateID = newTemplateServerID
            }
        }
        #if !os(macOS)
        .sheet(isPresented: $isShowingManagementSheet) {
            NavigationStack {
                TableTemplateManagementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isShowingManagementSheet = false }
                        }
                    }
            }
        }
        #endif
    }

    @ViewBuilder
    private func templateSection(_ title: String, templates: [CachedMetadataTableTemplate]) -> some View {
        if !templates.isEmpty {
            Section(title) {
                ForEach(templates) { template in
                    Button {
                        selectedTemplateID = template.serverID
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                Text("\(template.columnCount) columns")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTemplateID == template.serverID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("metadataTemplateRow_\(template.name)")
                }
            }
        }
    }

    private func save() async {
        guard let selectedTemplateID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.instrumentJobSync.createMetadataFromTemplate(
                jobServerID: jobServerID,
                jobClientID: jobClientID,
                templateID: selectedTemplateID,
                sampleCount: Int(sampleCountText)
            )
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
