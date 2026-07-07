import SwiftUI

/// Adds/edits a step's description and optional duration (entered as minutes, stored as seconds).
struct AddStepSheet: View {
    @Environment(\.dismiss) private var dismiss

    let navigationTitle: String
    let onSave: (_ description: String, _ durationSeconds: Int?) -> Void

    @State private var description: String
    @State private var durationMinutesText: String

    init(
        navigationTitle: String = "New Step",
        initialDescription: String = "",
        initialDurationSeconds: Int? = nil,
        onSave: @escaping (_ description: String, _ durationSeconds: Int?) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.onSave = onSave
        _description = State(initialValue: initialDescription)
        _durationMinutesText = State(initialValue: initialDurationSeconds.map { String($0 / 60) } ?? "")
    }

    private var trimmedDurationSeconds: Int? {
        guard !durationMinutesText.isEmpty, let minutes = Int(durationMinutesText) else { return nil }
        return minutes * 60
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What's this step?") {
                    TextField("Description", text: $description, axis: .vertical)
                        .accessibilityIdentifier("addTextSheetField")
                }
                Section("Duration") {
                    TextField("Minutes (optional)", text: $durationMinutesText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityIdentifier("stepDurationField")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(description, trimmedDurationSeconds)
                        dismiss()
                    }
                    .disabled(description.isEmpty)
                    .accessibilityIdentifier("addTextSheetSaveButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 280)
    }
}
