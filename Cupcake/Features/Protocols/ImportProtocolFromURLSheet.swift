import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct ImportProtocolFromURLSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("protocols.io URL", text: $url)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("protocolsIOURLField")
                } footer: {
                    Text("Paste a protocols.io link to import its title, sections, and steps.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import from protocols.io")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task { await importProtocol() }
                    }
                    .disabled(url.isEmpty || isImporting)
                    .accessibilityIdentifier("importProtocolButton")
                }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
        .alert("Couldn't import protocol", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func importProtocol() async {
        isImporting = true
        defer { isImporting = false }
        do {
            try await appSession.makeSyncServices().protocolSync.importFromProtocolsIO(url: url)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
