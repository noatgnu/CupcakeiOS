import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct ColumnFindReplaceSheet: View {
    let column: MetadataColumnDTO
    let onCompleted: () async -> Void

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    @State private var oldValue = ""
    @State private var newValue = ""
    @State private var updatePools = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var resultMessage: String?
    @State private var isShowingResult = false

    private var canApply: Bool {
        !oldValue.isEmpty && !newValue.isEmpty && oldValue != newValue
    }

    var body: some View {
        NavigationStack {
            Form {
                #if !os(macOS)
                Section {
                    Text(column.displayName ?? column.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                #endif
                Section("Replace") {
                    TextField("Find value", text: $oldValue)
                        .accessibilityIdentifier("findReplaceOldValueField")
                    TextField("Replace with", text: $newValue)
                        .accessibilityIdentifier("findReplaceNewValueField")
                }
                Section {
                    Toggle("Also update sample pools", isOn: $updatePools)
                        .accessibilityIdentifier("findReplaceUpdatePoolsToggle")
                } footer: {
                    Text("Replaces this exact value everywhere it's used in this column: the default value and any per-sample overrides, merging overlapping sample ranges automatically.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Find & Replace")
            #if os(macOS)
            .navigationSubtitle(column.displayName ?? column.name)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task { await apply() }
                    }
                    .disabled(isSaving || !canApply)
                    .accessibilityIdentifier("applyFindReplaceButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
        .alert("Couldn't replace value", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Replace Complete", isPresented: $isShowingResult) {
            Button("OK") { dismiss() }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func apply() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            let response = try await services.metadataColumnSync.replaceValue(
                columnServerID: column.id,
                oldValue: oldValue,
                newValue: newValue,
                updatePools: updatePools
            )
            var parts: [String] = []
            if response.defaultValueUpdated { parts.append("default value updated") }
            if response.modifiersMerged > 0 { parts.append("\(response.modifiersMerged) override(s) merged") }
            if response.modifiersDeleted > 0 { parts.append("\(response.samplesRevertedToDefault) sample(s) reverted to default") }
            if response.poolColumnsUpdated > 0 { parts.append("\(response.poolColumnsUpdated) pool column(s) updated") }
            resultMessage = parts.isEmpty ? "No matching values were found." : parts.joined(separator: ", ") + "."
            await onCompleted()
            isShowingResult = true
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
