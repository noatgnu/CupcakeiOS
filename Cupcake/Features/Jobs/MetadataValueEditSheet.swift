import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

/// Basic value editing — plain text + ontology typeahead, no favourites/recommendations or
/// SDRF special-syntax input yet (both deferred to a later slice; see the reference web app's
/// `MetadataValueEditModal` for the fuller design this will eventually grow toward).
struct MetadataValueEditSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let column: CachedMetadataColumn

    @State private var value: String
    @State private var suggestions: [OntologySuggestionDTO] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(column: CachedMetadataColumn) {
        self.column = column
        _value = State(initialValue: column.value ?? "")
    }

    private var hasOntologyType: Bool {
        column.ontologyType != nil && !column.readonly
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(column.displayName ?? column.name) {
                    TextField("Value", text: $value)
                        .accessibilityIdentifier("metadataValueField")
                        .onChange(of: value) {
                            scheduleSearch()
                        }
                    HStack {
                        Button("Not Applicable") { value = "not applicable" }
                            .accessibilityIdentifier("metadataValueNotApplicableButton")
                        Spacer()
                        Button("Not Available") { value = "not available" }
                            .accessibilityIdentifier("metadataValueNotAvailableButton")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                if hasOntologyType, !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions) { suggestion in
                            Button {
                                value = suggestion.displayName
                                suggestions = []
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(suggestion.displayName)
                                    if let description = suggestion.description, !description.isEmpty, description != suggestion.displayName {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Value")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || column.readonly)
                    .accessibilityIdentifier("saveMetadataValueButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .alert("Couldn't save value", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard hasOntologyType else { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let services = appSession.makeSyncServices()
                let results = try await services.metadataColumnSync.fetchOntologySuggestions(columnServerID: column.serverID, search: value)
                guard !Task.isCancelled else { return }
                suggestions = results
            } catch {
                // Non-fatal — a failed typeahead search shouldn't block manual value entry.
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataColumnSync.updateColumnValue(columnServerID: column.serverID, value: value)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
