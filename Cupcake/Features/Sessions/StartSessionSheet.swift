import SwiftUI

/// Field set verified against the reference web app's `session-create-modal.ts`: `name`
/// (required, pre-filled with a sensible default here but editable) and `enabled` ("Public" in
/// the web UI) — the session is always created for the current protocol context, never a
/// user-picked one, matching `session-create-modal.html`'s "A new session will be created for
/// this protocol" copy.
struct StartSessionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let defaultName: String
    let onSave: (_ name: String, _ enabled: Bool) -> Void

    @State private var name: String
    @State private var enabled = true

    init(defaultName: String, onSave: @escaping (_ name: String, _ enabled: Bool) -> Void) {
        self.defaultName = defaultName
        self.onSave = onSave
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Session name", text: $name)
                        .accessibilityIdentifier("sessionNameField")
                    Toggle("Public", isOn: $enabled)
                        .accessibilityIdentifier("sessionEnabledToggle")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onSave(name, enabled)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .accessibilityIdentifier("startSessionButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 220)
    }
}
