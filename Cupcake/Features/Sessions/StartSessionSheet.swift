import SwiftUI

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
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 220)
        #endif
    }
}
