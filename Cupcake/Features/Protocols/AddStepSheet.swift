import SwiftUI

/// Distinct from `AddTextSheet` because a step (unlike a section, per the reference web app) can
/// carry an optional duration — a real, populated field for protocols.io-imported protocols
/// (`ProtocolStepDTO.stepDuration`), so local authoring should be able to set it too.
///
/// The stored/passed-out value is **seconds**, matching the backend field — verified against the
/// reference web app's `duration-input.ts`, which decomposes a step's duration into day/hour/
/// min/sec sub-fields, not a bare minutes number. This form simplifies that to a single "minutes"
/// input (converted to seconds on save) rather than reproducing the full composite widget — a
/// deliberate UI simplification, not a misunderstanding of the underlying unit.
///
/// The parent section's own duration is never entered here — it's derived automatically as the
/// sum of its steps' durations (`ProtocolDetailView.recomputeSectionDuration(for:)`), a
/// deliberate divergence from the reference app (there, section duration is independently
/// editable, not computed) made for this app's local-authoring flow specifically.
struct AddStepSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (_ description: String, _ durationSeconds: Int?) -> Void

    @State private var description = ""
    @State private var durationMinutesText = ""

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
            .navigationTitle("New Step")
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
