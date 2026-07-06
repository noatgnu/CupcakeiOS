import CupcakeModels
import CupcakeSync
import SwiftData
import SwiftUI

struct CreateMetadataFromTemplateSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CachedMetadataTableTemplate.name) private var templates: [CachedMetadataTableTemplate]

    let jobClientID: UUID
    let jobServerID: Int64
    let defaultSampleCount: Int?

    @State private var selectedTemplateID: Int64?
    @State private var sampleCountText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(jobClientID: UUID, jobServerID: Int64, defaultSampleCount: Int?) {
        self.jobClientID = jobClientID
        self.jobServerID = jobServerID
        self.defaultSampleCount = defaultSampleCount
        _sampleCountText = State(initialValue: defaultSampleCount.map(String.init) ?? "")
    }

    private var canSave: Bool {
        selectedTemplateID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if templates.isEmpty {
                    Text("No metadata table templates available.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Template") {
                        Picker("Template", selection: $selectedTemplateID) {
                            Text("None").tag(Int64?.none)
                            ForEach(templates) { template in
                                Text("\(template.name) (\(template.columnCount) columns)").tag(Optional(template.serverID))
                            }
                        }
                        .accessibilityIdentifier("metadataTemplatePicker")
                    }
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
        .frame(minWidth: 360, minHeight: 300)
        .alert("Couldn't create metadata table", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
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
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}
