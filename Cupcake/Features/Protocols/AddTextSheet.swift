import SwiftUI

/// A minimal single-field entry sheet — reused for renaming a section (`initialText` pre-fills
/// the current name) and any other plain "type a description, save it locally" case.
struct AddTextSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let prompt: String
    let onSave: (String) -> Void

    @State private var text: String

    init(title: String, prompt: String, initialText: String = "", onSave: @escaping (String) -> Void) {
        self.title = title
        self.prompt = prompt
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(prompt, text: $text, axis: .vertical)
                    .accessibilityIdentifier("addTextSheetField")
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.isEmpty)
                    .accessibilityIdentifier("addTextSheetSaveButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 220)
    }
}
