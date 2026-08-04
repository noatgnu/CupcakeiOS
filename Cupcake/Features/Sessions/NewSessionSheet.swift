import CupcakeModels
import SwiftData
import SwiftUI

struct NewSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CachedProtocol.createdAt, order: .reverse) private var allProtocols: [CachedProtocol]

    let onSave: (_ name: String, _ enabled: Bool, _ protocolClientIDs: [UUID]) -> Void

    @State private var name = ""
    @State private var enabled = true
    @State private var selectedProtocolClientIDs: Set<UUID> = []
    @State private var protocolSearchText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Session name", text: $name)
                        .accessibilityIdentifier("newSessionNameField")
                    Toggle("Public", isOn: $enabled)
                        .accessibilityIdentifier("newSessionEnabledToggle")
                }
                Section("Protocols (optional)") {
                    SearchableSelectionList(
                        items: allProtocols,
                        searchPlaceholder: "Search protocols",
                        searchFieldIdentifier: "newSessionProtocolSearchField",
                        searchText: $protocolSearchText,
                        matches: { $0.protocolTitle.localizedCaseInsensitiveContains($1) },
                        isSelected: { selectedProtocolClientIDs.contains($0.clientID) },
                        rowIdentifier: { "newSessionProtocolRow_\($0.protocolTitle)" },
                        onSelect: { toggle($0.clientID) }
                    ) { protocolModel in
                        Text(protocolModel.protocolTitle)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave(name, enabled, Array(selectedProtocolClientIDs))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .accessibilityIdentifier("createSessionButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 400)
        #endif
    }

    private func toggle(_ clientID: UUID) {
        if selectedProtocolClientIDs.contains(clientID) {
            selectedProtocolClientIDs.remove(clientID)
        } else {
            selectedProtocolClientIDs.insert(clientID)
        }
    }
}
