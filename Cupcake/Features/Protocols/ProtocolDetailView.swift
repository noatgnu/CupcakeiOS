import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Identifies which protocol to show when `ProtocolDetailView` opens as its own window.
struct ProtocolDetailWindowID: Codable, Hashable {
    let protocolClientID: UUID
}

/// Resolves a `ProtocolDetailWindowID` to the live protocol and hosts `ProtocolDetailView`.
struct ProtocolDetailWindowContent: View {
    let windowID: ProtocolDetailWindowID?

    @Query private var protocols: [CachedProtocol]

    private var protocolModel: CachedProtocol? {
        guard let windowID else { return nil }
        return protocols.first { $0.clientID == windowID.protocolClientID }
    }

    var body: some View {
        if let protocolModel {
            NavigationStack {
                ProtocolDetailView(protocolModel: protocolModel)
            }
        } else {
            ContentUnavailableView("Protocol Not Found", systemImage: "questionmark.square.dashed")
        }
    }
}

struct ProtocolDetailView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var allStepReagents: [CachedStepReagent]
    @Query private var allReagents: [CachedReagent]
    let protocolModel: CachedProtocol

    @State private var isCreatingSession = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var createdSessionClientID: UUID?
    @State private var newStepTargetSection: CachedProtocolSection?
    @State private var reagentAttachmentTargetStep: CachedProtocolStep?
    @State private var isShowingStartSessionSheet = false
    @State private var renameSectionTarget: CachedProtocolSection?
    @State private var exportURL: URL?
    @State private var isLoadingExport = false
    @State private var isShowingRatingSheet = false
    @State private var isShowingEditSheet = false
    @State private var isDeleting = false
    @State private var editStepTarget: CachedProtocolStep?
    @State private var editReagentTarget: CachedStepReagent?

    private var sections: [CachedProtocolSection] {
        protocolModel.sections.sorted { $0.order < $1.order }
    }

    /// Whether creates should go straight to the server or be created locally instead.
    private var canAuthorOnline: Bool {
        protocolModel.serverID != nil && appSession.isAuthenticated
    }

    /// A protocol this app authored stays editable, regardless of whether it has synced.
    private var isEditable: Bool {
        protocolModel.isLocallyAuthored
    }

    private func stepReagents(for step: CachedProtocolStep) -> [(stepReagent: CachedStepReagent, reagent: CachedReagent)] {
        allStepReagents
            .filter { $0.stepClientID == step.clientID }
            .compactMap { stepReagent in
                guard let reagent = allReagents.first(where: { $0.clientID == stepReagent.reagentClientID }) else { return nil }
                return (stepReagent, reagent)
            }
    }

    /// Shows `scaledQuantity = quantity * scalableFactor` for scalable reagents.
    private func reagentDisplayText(_ entry: (stepReagent: CachedStepReagent, reagent: CachedReagent)) -> String {
        let base = "\(entry.reagent.name): \(entry.stepReagent.quantity.formatted()) \(entry.reagent.unit)"
        guard entry.stepReagent.scalable else { return base }
        let scaled = entry.stepReagent.quantity * entry.stepReagent.scalableFactor
        return "\(base) — ×\(entry.stepReagent.scalableFactor.formatted()) = \(scaled.formatted()) \(entry.reagent.unit)"
    }

    /// Strips HTML markup from the section description for use as a plain-text title.
    private func sectionTitle(_ section: CachedProtocolSection) -> String {
        let base = section.sectionDescription.map(HTMLText.plainText(from:)) ?? "Untitled Section"
        guard let duration = section.sectionDuration else { return base }
        return "\(base) (\(HumanReadableDuration.format(seconds: duration)))"
    }

    private func stepDurationLabel(_ step: CachedProtocolStep) -> String? {
        guard let duration = step.stepDuration else { return nil }
        return HumanReadableDuration.format(seconds: duration)
    }

    var body: some View {
        sectionsList
            .navigationTitle(protocolModel.protocolTitle)
        .toolbar { detailToolbar }
        .navigationDestination(item: $createdSessionClientID) { sessionClientID in
            SessionDetailView(sessionClientID: sessionClientID, protocols: [protocolModel])
        }
        .sheet(item: $renameSectionTarget) { section in
            AddTextSheet(title: "Rename Section", prompt: "Section name", initialText: section.sectionDescription ?? "") { newName in
                Task { await renameSection(section, to: newName) }
            }
        }
        .sheet(item: $newStepTargetSection) { section in
            AddStepSheet { description, duration in
                Task { await addStep(description: description, duration: duration, to: section) }
            }
        }
        .sheet(item: $editStepTarget) { step in
            AddStepSheet(
                navigationTitle: "Edit Step",
                initialDescription: HTMLText.plainText(from: step.stepDescription),
                initialDurationSeconds: step.stepDuration
            ) { description, duration in
                Task { await editStep(step, description: description, duration: duration) }
            }
        }
        .sheet(item: $editReagentTarget) { stepReagent in
            EditStepReagentSheet(stepReagent: stepReagent)
        }
        .sheet(item: $reagentAttachmentTargetStep) { step in
            AttachReagentSheet(step: step, canAuthorOnline: canAuthorOnline)
        }
        .sheet(isPresented: $isShowingRatingSheet) {
            if let protocolServerID = protocolModel.serverID {
                RateProtocolSheet(protocolServerID: protocolServerID)
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            EditProtocolSheet(protocolModel: protocolModel)
        }
        .task {
            guard let protocolServerID = protocolModel.serverID, let userID = appSession.currentUserID else { return }
            try? await appSession.makeSyncServices().protocolRatingSync.refetchMyRating(protocolServerID: protocolServerID, userID: userID)
        }
        .sheet(isPresented: $isShowingStartSessionSheet) {
            StartSessionSheet(defaultName: "\(protocolModel.protocolTitle) — \(Date().formatted(date: .abbreviated, time: .shortened))") { name, enabled in
                Task { await startSession(name: name, enabled: enabled) }
            }
        }
        .alert("Couldn't start session", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sectionsList: some View {
        ExplorerList(
            isEmpty: sections.isEmpty,
            emptyTitle: "No Sections",
            emptySystemImage: "list.bullet.rectangle",
            emptyMessage: isEditable ? "Add a section to get started." : "This protocol has no sections."
        ) {
            ForEach(sections) { section in
                Section(sectionTitle(section)) {
                    ForEach(section.steps.sorted(by: { $0.order < $1.order })) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            HTMLText(html: StepTemplateRenderer.render(stepDescription: step.stepDescription, reagents: stepReagents(for: step)))
                            if let durationLabel = stepDurationLabel(step) {
                                Text(durationLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(stepReagents(for: step), id: \.stepReagent.clientID) { entry in
                                HStack {
                                    Button {
                                        editReagentTarget = entry.stepReagent
                                    } label: {
                                        Text(reagentDisplayText(entry))
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("editReagentButton_\(entry.stepReagent.clientID)")
                                    if entry.stepReagent.serverID != nil {
                                        Spacer()
                                        Button {
                                            Task { await deleteReagent(entry.stepReagent) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.red)
                                        .accessibilityIdentifier("deleteReagentButton_\(entry.stepReagent.clientID)")
                                    }
                                }
                            }
                            HStack {
                                Button {
                                    reagentAttachmentTargetStep = step
                                } label: {
                                    Label("Attach Reagent", systemImage: "eyedropper")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("attachReagentButton")
                                if isEditable {
                                    Button {
                                        editStepTarget = step
                                    } label: {
                                        Label("Edit Step", systemImage: "pencil")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("editStepButton")
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let sortedSteps = section.steps.sorted { $0.order < $1.order }
                        Task { await deleteSteps(at: offsets, from: sortedSteps) }
                    }
                    if isEditable {
                        // Vertical stack avoids horizontal overflow on narrow iPhone widths.
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                newStepTargetSection = section
                            } label: {
                                Label("Add Step", systemImage: "plus")
                            }
                            .accessibilityIdentifier("addStepButton")

                            Button {
                                renameSectionTarget = section
                            } label: {
                                Label("Rename Section", systemImage: "pencil")
                            }
                            .accessibilityIdentifier("renameSectionButton")

                            if section.serverID != nil {
                                Button(role: .destructive) {
                                    Task { await deleteSection(section) }
                                } label: {
                                    Label("Delete Section", systemImage: "trash")
                                }
                                .accessibilityIdentifier("deleteSectionButton")
                            }
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if isEditable {
            ToolbarItem {
                Button {
                    Task { await addSection() }
                } label: {
                    Label("Add Section", systemImage: "text.badge.plus")
                }
                .accessibilityIdentifier("addSectionButton")
            }
        }
        if protocolModel.serverID != nil {
            ToolbarItem {
                Button {
                    isShowingEditSheet = true
                } label: {
                    Label("Edit Protocol", systemImage: "pencil")
                }
                .accessibilityIdentifier("editProtocolButton")
            }
            ToolbarItem {
                Button(role: .destructive) {
                    Task { await deleteProtocol() }
                } label: {
                    if isDeleting {
                        ProgressView()
                    } else {
                        Label("Delete Protocol", systemImage: "trash")
                    }
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("deleteProtocolButton")
            }
        }
        ToolbarItem {
            Button {
                isShowingStartSessionSheet = true
            } label: {
                if isCreatingSession {
                    ProgressView()
                } else {
                    Label("New Session", systemImage: "plus")
                }
            }
            .disabled(isCreatingSession)
            .accessibilityIdentifier("newSessionButton")
        }
        if PlatformWindowPreference.prefersSeparateWindow {
            ToolbarItem {
                Button {
                    openWindow(id: "protocol-detail-window", value: ProtocolDetailWindowID(protocolClientID: protocolModel.clientID))
                } label: {
                    Label("Open in New Window", systemImage: "macwindow.badge.plus")
                }
                .accessibilityIdentifier("openProtocolInWindowButton")
            }
        }
        if protocolModel.serverID != nil {
            ToolbarItem {
                Button {
                    isShowingRatingSheet = true
                } label: {
                    Label("Rate Protocol", systemImage: "star")
                }
                .accessibilityIdentifier("rateProtocolButton")
            }
        }
        if protocolModel.serverID != nil {
            ToolbarItem {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export as HTML", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportProtocolButton")
                } else {
                    Button {
                        Task { await loadExportURL() }
                    } label: {
                        if isLoadingExport {
                            ProgressView()
                        } else {
                            Label("Export as HTML", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isLoadingExport)
                    .accessibilityIdentifier("exportProtocolButton")
                }
            }
        }
    }

    private func loadExportURL() async {
        guard let serverID = protocolModel.serverID else { return }
        isLoadingExport = true
        defer { isLoadingExport = false }
        do {
            exportURL = try await appSession.makeSyncServices().protocolSync.fetchExportURL(protocolServerID: serverID, sessionServerID: nil)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func deleteProtocol() async {
        guard let serverID = protocolModel.serverID else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await appSession.makeSyncServices().protocolSync.delete(serverID: serverID)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    /// Creates a section locally with a default name, then syncs immediately or queues it in the outbox.
    private func addSection() async {
        let description = "New Section \(sections.count + 1)"
        let order = sections.count
        let section = CachedProtocolSection(sectionDescription: description, order: order, protocolModel: protocolModel)
        modelContext.insert(section)
        try? modelContext.save()

        guard canAuthorOnline else { return }
        let clientID = section.clientID
        let services = appSession.makeSyncServices()
        do {
            // Write the returned serverID directly onto this context's own object.
            let newServerID = try await services.protocolSync.syncLocallyCreatedSection(clientID: clientID, knownProtocolServerID: protocolModel.serverID)
            section.serverID = newServerID
            try? modelContext.save()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateSection(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch is SyncDependencyError {
            try? await services.outboxSync.enqueueCreateSection(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    /// Same create-locally-then-sync-or-queue shape as `addSection`.
    private func addStep(description: String, duration: Int?, to section: CachedProtocolSection) async {
        let order = section.steps.count
        let step = CachedProtocolStep(stepDescription: description, order: order, stepDuration: duration, section: section)
        modelContext.insert(step)
        recomputeSectionDuration(for: section)
        try? modelContext.save()

        guard canAuthorOnline else { return }
        let clientID = step.clientID
        let services = appSession.makeSyncServices()
        do {
            let newServerID = try await services.protocolSync.syncLocallyCreatedStep(clientID: clientID, knownSectionServerID: section.serverID, knownProtocolServerID: protocolModel.serverID)
            step.serverID = newServerID
            try? modelContext.save()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateStep(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch is SyncDependencyError {
            try? await services.outboxSync.enqueueCreateStep(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func renameSection(_ section: CachedProtocolSection, to newName: String) async {
        section.sectionDescription = newName
        try? modelContext.save()
        guard canAuthorOnline, let serverID = section.serverID else { return }
        do {
            try await appSession.makeSyncServices().protocolSync.updateSection(serverID: serverID, sectionDescription: newName, sectionDuration: section.sectionDuration)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func deleteSection(_ section: CachedProtocolSection) async {
        guard let serverID = section.serverID else { return }
        do {
            try await appSession.makeSyncServices().protocolSync.deleteSection(serverID: serverID)
            modelContext.delete(section)
            try? modelContext.save()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func editStep(_ step: CachedProtocolStep, description: String, duration: Int?) async {
        step.stepDescription = description
        step.stepDuration = duration
        if let section = step.section {
            recomputeSectionDuration(for: section)
        }
        try? modelContext.save()
        guard canAuthorOnline, let serverID = step.serverID else { return }
        do {
            try await appSession.makeSyncServices().protocolSync.updateStep(serverID: serverID, stepDescription: description, stepDuration: duration)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func deleteSteps(at offsets: IndexSet, from sortedSteps: [CachedProtocolStep]) async {
        let stepsToRemove = offsets.map { sortedSteps[$0] }
        for step in stepsToRemove {
            guard let serverID = step.serverID else {
                modelContext.delete(step)
                continue
            }
            do {
                try await appSession.makeSyncServices().protocolSync.deleteStep(serverID: serverID)
                modelContext.delete(step)
            } catch {
                errorMessage = error.userFacingMessage
                isShowingError = true
            }
        }
        try? modelContext.save()
    }

    private func deleteReagent(_ stepReagent: CachedStepReagent) async {
        guard let serverID = stepReagent.serverID else { return }
        do {
            try await appSession.makeSyncServices().stepReagentSync.delete(serverID: serverID)
            modelContext.delete(stepReagent)
            try? modelContext.save()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    /// Recomputes a section's duration as the sum of its steps' durations, or `nil` if none set.
    private func recomputeSectionDuration(for section: CachedProtocolSection) {
        let durations = section.steps.compactMap(\.stepDuration)
        section.sectionDuration = durations.isEmpty ? nil : durations.reduce(0, +)
    }

    private func startSession(name: String, enabled: Bool) async {
        isCreatingSession = true
        defer { isCreatingSession = false }

        let (clientID, outcome) = await SessionCreation.createSession(
            name: name,
            enabled: enabled,
            protocolClientIDs: [protocolModel.clientID],
            canAuthorOnline: canAuthorOnline,
            modelContext: modelContext,
            appSession: appSession
        )
        createdSessionClientID = clientID
        if case .failed(let message) = outcome {
            errorMessage = "Saved locally, but couldn't sync: \(message)"
            isShowingError = true
        }
    }
}
