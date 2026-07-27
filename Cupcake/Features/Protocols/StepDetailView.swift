import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct StepDetailWindowID: Codable, Hashable {
    let stepClientID: UUID
}

struct StepDetailWindowContent: View {
    let windowID: StepDetailWindowID?

    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Query private var allSteps: [CachedProtocolStep]

    private var step: CachedProtocolStep? {
        guard let windowID else { return nil }
        return allSteps.first { $0.clientID == windowID.stepClientID }
    }

    private var protocolModel: CachedProtocol? {
        step?.section?.protocolModel
    }

    private var canAuthorOnline: Bool {
        protocolModel?.serverID != nil && appSession.isAuthenticated
    }

    private var isEditable: Bool {
        protocolModel?.isLocallyAuthored ?? false
    }

    var body: some View {
        if let step {
            NavigationStack {
                StepDetailView(
                    stepClientID: step.clientID,
                    canAuthorOnline: canAuthorOnline,
                    isEditable: isEditable,
                    onEditStep: { step, description, duration in
                        await editStep(step, description: description, duration: duration)
                    },
                    onDeleteReagent: { stepReagent in
                        await deleteReagent(stepReagent)
                    }
                )
            }
        } else {
            ContentUnavailableView("Step Not Found", systemImage: "questionmark.square.dashed")
        }
    }

    private func editStep(_ step: CachedProtocolStep, description: String, duration: Int?) async {
        step.stepDescription = description
        step.stepDuration = duration
        if let section = step.section {
            let durations = section.steps.compactMap(\.stepDuration)
            section.sectionDuration = durations.isEmpty ? nil : durations.reduce(0, +)
        }
        try? modelContext.save()
        guard canAuthorOnline, let serverID = step.serverID else { return }
        _ = try? await appSession.makeSyncServices().protocolSync.updateStep(serverID: serverID, stepDescription: description, stepDuration: duration)
    }

    private func deleteReagent(_ stepReagent: CachedStepReagent) async {
        guard let serverID = stepReagent.serverID else { return }
        try? await appSession.makeSyncServices().stepReagentSync.delete(serverID: serverID)
        modelContext.delete(stepReagent)
        try? modelContext.save()
    }
}

struct StepDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var allSteps: [CachedProtocolStep]
    @Query private var allStepReagents: [CachedStepReagent]
    @Query private var allReagents: [CachedReagent]

    let stepClientID: UUID
    let canAuthorOnline: Bool
    let isEditable: Bool
    let onEditStep: (_ step: CachedProtocolStep, _ descriptionHTML: String, _ durationSeconds: Int?) async -> Void
    let onDeleteReagent: (_ stepReagent: CachedStepReagent) async -> Void

    @State private var editStepTarget: CachedProtocolStep?
    @State private var reagentAttachmentTargetStep: CachedProtocolStep?
    @State private var editReagentTarget: CachedStepReagent?
    @State private var editStepDraftHTML: String?
    @State private var editStepDraftDuration: Int?
    @State private var editStepReturnTarget: CachedProtocolStep?
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var step: CachedProtocolStep? {
        allSteps.first { $0.clientID == stepClientID }
    }

    private var reagents: [(stepReagent: CachedStepReagent, reagent: CachedReagent)] {
        guard let step else { return [] }
        return allStepReagents
            .filter { $0.stepClientID == step.clientID }
            .compactMap { stepReagent in
                guard let reagent = allReagents.first(where: { $0.clientID == stepReagent.reagentClientID }) else { return nil }
                return (stepReagent, reagent)
            }
    }

    var body: some View {
        Group {
            if let step {
                Form {
                    Section("Description") {
                        HTMLText(html: StepTemplateRenderer.render(stepDescription: step.stepDescription, reagents: reagents))
                        if let duration = step.stepDuration {
                            Text(HumanReadableDuration.format(seconds: duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Reagents") {
                        ForEach(reagents, id: \.stepReagent.clientID) { entry in
                            HStack {
                                Button {
                                    editReagentTarget = entry.stepReagent
                                } label: {
                                    Text(reagentDisplayText(entry))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("editReagentButton_\(entry.stepReagent.clientID)")
                                if entry.stepReagent.serverID != nil {
                                    Spacer()
                                    Button(role: .destructive) {
                                        Task { await onDeleteReagent(entry.stepReagent) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("deleteReagentButton_\(entry.stepReagent.clientID)")
                                    .help("Remove Reagent")
                                }
                            }
                        }
                        Button {
                            reagentAttachmentTargetStep = step
                        } label: {
                            Label("Attach Reagent", systemImage: "eyedropper")
                        }
                        .accessibilityIdentifier("attachReagentButton")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Step")
                .toolbar {
                    if isEditable {
                        ToolbarItem {
                            Button {
                                editStepTarget = step
                            } label: {
                                Label("Edit Step", systemImage: "pencil")
                            }
                            .accessibilityIdentifier("editStepButton")
                        }
                    }
                    if PlatformWindowPreference.prefersSeparateWindow {
                        ToolbarItem {
                            Button {
                                openWindow(id: "step-detail-window", value: StepDetailWindowID(stepClientID: stepClientID))
                            } label: {
                                Label("Open in New Window", systemImage: "macwindow.badge.plus")
                            }
                            .accessibilityIdentifier("openStepInWindowButton")
                        }
                    }
                }
                .sheet(item: $editStepTarget, onDismiss: {
                    if let target = editStepReturnTarget {
                        reagentAttachmentTargetStep = target
                    }
                }) { target in
                    AddStepSheet(
                        navigationTitle: "Edit Step",
                        initialDescriptionHTML: editStepDraftHTML ?? target.stepDescription,
                        initialDurationSeconds: editStepDraftDuration ?? target.stepDuration,
                        stepReagents: reagents,
                        onAttachNewReagent: { draftHTML, draftDuration in
                            editStepDraftHTML = draftHTML
                            editStepDraftDuration = draftDuration
                            editStepReturnTarget = target
                            editStepTarget = nil
                        }
                    ) { description, duration in
                        editStepDraftHTML = nil
                        editStepDraftDuration = nil
                        Task { await onEditStep(target, description, duration) }
                    }
                }
                .sheet(item: $reagentAttachmentTargetStep, onDismiss: {
                    if let target = editStepReturnTarget {
                        editStepReturnTarget = nil
                        editStepTarget = target
                    }
                }) { target in
                    AttachReagentSheet(step: target, canAuthorOnline: canAuthorOnline)
                }
                .sheet(item: $editReagentTarget) { stepReagent in
                    EditStepReagentSheet(stepReagent: stepReagent)
                }
            } else {
                ContentUnavailableView("Step Not Found", systemImage: "questionmark.square.dashed")
            }
        }
        .alert("Couldn't save", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reagentDisplayText(_ entry: (stepReagent: CachedStepReagent, reagent: CachedReagent)) -> String {
        let base = "\(entry.reagent.name): \(entry.stepReagent.quantity.formatted()) \(entry.reagent.unit)"
        guard entry.stepReagent.scalable else { return base }
        let scaled = entry.stepReagent.quantity * entry.stepReagent.scalableFactor
        return "\(base) (×\(entry.stepReagent.scalableFactor.formatted()) = \(scaled.formatted()) \(entry.reagent.unit))"
    }
}
