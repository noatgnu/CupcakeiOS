import CupcakeModels
import SwiftData
import SwiftUI

/// Creates a session from the Sessions tab, attaching 0..N protocols up front.
struct NewSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CachedProtocol.protocolTitle) private var allProtocols: [CachedProtocol]

    let onSave: (_ name: String, _ enabled: Bool, _ protocolClientIDs: [UUID]) -> Void

    @State private var name = ""
    @State private var enabled = true
    @State private var selectedProtocolClientIDs: Set<UUID> = []

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
                    ForEach(allProtocols) { protocolModel in
                        Button {
                            toggle(protocolModel.clientID)
                        } label: {
                            HStack {
                                Text(protocolModel.protocolTitle)
                                Spacer()
                                if selectedProtocolClientIDs.contains(protocolModel.clientID) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("newSessionProtocolRow_\(protocolModel.protocolTitle)")
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
        .frame(minWidth: 360, minHeight: 400)
    }

    private func toggle(_ clientID: UUID) {
        if selectedProtocolClientIDs.contains(clientID) {
            selectedProtocolClientIDs.remove(clientID)
        } else {
            selectedProtocolClientIDs.insert(clientID)
        }
    }
}
