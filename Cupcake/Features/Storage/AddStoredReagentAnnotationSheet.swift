import CupcakeNetworking
import CupcakeSync
import SwiftUI

/// Creates a document/note for a stored reagent, filed into one of its predefined folders. Online-only.
struct AddStoredReagentAnnotationSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let storedReagentServerID: Int64
    let reagentName: String

    @State private var folders: [AnnotationFolderDTO] = []
    @State private var selectedFolderID: Int64?
    @State private var text = ""
    @State private var isLoadingFolders = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isLoadingFolders {
                        ProgressView()
                    } else {
                        Picker("Folder", selection: $selectedFolderID) {
                            ForEach(folders, id: \.id) { folder in
                                Text(folder.folderName).tag(Optional(folder.id))
                            }
                        }
                        .accessibilityIdentifier("storedReagentAnnotationFolderPicker")
                    }
                    TextField("Note", text: $text, axis: .vertical)
                        .accessibilityIdentifier("storedReagentAnnotationTextField")
                } footer: {
                    Text("Adding a document for \(reagentName).")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || selectedFolderID == nil || text.isEmpty)
                    .accessibilityIdentifier("saveStoredReagentAnnotationButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .task {
            await loadFolders()
        }
        .alert("Couldn't save document", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadFolders() async {
        isLoadingFolders = true
        defer { isLoadingFolders = false }
        do {
            folders = try await appSession.makeSyncServices().storedReagentAnnotationSync.fetchDocumentFolders()
            selectedFolderID = folders.first?.id
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func save() async {
        guard let folderID = selectedFolderID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appSession.makeSyncServices().storedReagentAnnotationSync.create(
                storedReagentServerID: storedReagentServerID,
                folderServerID: folderID,
                text: text
            )
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
