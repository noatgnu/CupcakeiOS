import CupcakeModels
import SwiftUI

struct AddStepSheet: View {
    @Environment(\.dismiss) private var dismiss

    let navigationTitle: String
    let stepReagents: [(stepReagent: CachedStepReagent, reagent: CachedReagent)]
    let onAttachNewReagent: ((_ draftHTML: String, _ draftDurationSeconds: Int?) -> Void)?
    let onSave: (_ descriptionHTML: String, _ durationSeconds: Int?) -> Void

    @State private var description: String
    @State private var durationMinutesText: String

    init(
        navigationTitle: String = "New Step",
        initialDescriptionHTML: String = "",
        initialDurationSeconds: Int? = nil,
        stepReagents: [(stepReagent: CachedStepReagent, reagent: CachedReagent)] = [],
        onAttachNewReagent: ((_ draftHTML: String, _ draftDurationSeconds: Int?) -> Void)? = nil,
        onSave: @escaping (_ descriptionHTML: String, _ durationSeconds: Int?) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.stepReagents = stepReagents
        self.onAttachNewReagent = onAttachNewReagent
        self.onSave = onSave
        _description = State(initialValue: initialDescriptionHTML)
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
                    StepRichTextEditor(
                        html: $description,
                        stepReagents: stepReagents,
                        onAttachNewReagent: onAttachNewReagent.map { callback in
                            { callback(description, trimmedDurationSeconds) }
                        }
                    )
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
                    .accessibilityIdentifier("addStepSaveButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}
