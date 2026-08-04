import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct ProtocolDetailWindowID: Codable, Hashable {
    let namespaceID: UUID
    let protocolClientID: UUID
}

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
    @Environment(\.namespaceID) private var namespaceID
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var allStepReagents: [CachedStepReagent]
    @Query private var allReagents: [CachedReagent]
    let protocolModel: CachedProtocol

    @State private var isCreatingSession = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var createdSessionClientID: UUID?
    @State private var newStepTargetSection: CachedProtocolSection?
    @State private var isShowingStartSessionSheet = false
    @State private var renameSectionTarget: CachedProtocolSection?
    @State private var exportURL: URL?
    @State private var isLoadingExport = false
    @State private var isShowingRatingSheet = false
    @State private var isShowingEditSheet = false
    @State private var isDeleting = false
    @State private var stepDetailTarget: UUID?
    @State private var selectedSectionID: UUID?
    @State private var isShowingAccessSheet = false

    private var sections: [CachedProtocolSection] {
        protocolModel.sections.sorted { $0.order < $1.order }
    }

    private var selectedSection: CachedProtocolSection? {
        sections.first { $0.clientID == selectedSectionID } ?? sections.first
    }

    private var canAuthorOnline: Bool {
        protocolModel.serverID != nil && appSession.isAuthenticated
    }

    private var isOwner: Bool {
        protocolModel.serverID != nil && protocolModel.ownerServerID != nil && protocolModel.ownerServerID == appSession.currentUserID
    }

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
        Group {
            if horizontalSizeClass == .compact {
                compactBody
            } else {
                regularBody
            }
        }
        .navigationTitle(protocolModel.protocolTitle)
        .toolbar { detailToolbar }
        .navigationDestination(item: $createdSessionClientID) { sessionClientID in
            SessionDetailView(sessionClientID: sessionClientID, protocols: [protocolModel])
        }
        .navigationDestination(item: $stepDetailTarget) { stepClientID in
            StepDetailView(
                stepClientID: stepClientID,
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
        .sheet(item: $renameSectionTarget) { section in
            AddTextSheet(title: "Edit Section", prompt: "Section name", initialText: section.sectionDescription ?? "") { newName in
                Task { await renameSection(section, to: newName) }
            }
        }
        .sheet(item: $newStepTargetSection) { section in
            AddStepSheet { description, duration in
                Task { await addStep(description: description, duration: duration, to: section) }
            }
        }
        .sheet(isPresented: $isShowingRatingSheet) {
            if let protocolServerID = protocolModel.serverID {
                RateProtocolSheet(protocolServerID: protocolServerID)
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            EditProtocolSheet(protocolModel: protocolModel)
        }
        .sheet(isPresented: $isShowingAccessSheet) {
            if let protocolServerID = protocolModel.serverID {
                AccessManagementView(target: .protocolResource(serverID: protocolServerID))
            }
        }
        .task {
            guard let protocolServerID = protocolModel.serverID, let userID = appSession.currentUserID else { return }
            try? await appSession.makeSyncServices().protocolRatingSync.refetchMyRating(protocolServerID: protocolServerID, userID: userID)
        }
        .sheet(isPresented: $isShowingStartSessionSheet) {
            StartSessionSheet(defaultName: "\(protocolModel.protocolTitle), \(Date().formatted(date: .abbreviated, time: .shortened))") { name, enabled in
                Task { await startSession(name: name, enabled: enabled) }
            }
        }
        .alert("Couldn't start session", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var regularBody: some View {
        HStack(spacing: 0) {
            sectionSidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            Divider()
            if let selectedSection {
                sectionDetailContent(selectedSection)
            } else {
                ContentUnavailableView("No Sections", systemImage: "list.bullet.rectangle", description: Text(isEditable ? "Add a section to get started." : "This protocol has no sections."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var compactBody: some View {
        ExplorerList(
            isEmpty: sections.isEmpty,
            emptyTitle: "No Sections",
            emptySystemImage: "list.bullet.rectangle",
            emptyMessage: isEditable ? "Add a section to get started." : "This protocol has no sections."
        ) {
            ForEach(Array(sections.enumerated()), id: \.element.clientID) { index, section in
                Button {
                    selectedSectionID = section.clientID
                } label: {
                    sectionRowLabel(section, number: index + 1)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sectionRow_\(section.clientID)")
            }
        }
        .navigationDestination(item: $selectedSectionID) { sectionID in
            if let section = sections.first(where: { $0.clientID == sectionID }) {
                sectionDetailContent(section)
                    .navigationTitle(sectionTitle(section))
            }
        }
    }

    private var sectionSidebar: some View {
        SelectableExplorerList(
            selection: $selectedSectionID,
            isEmpty: sections.isEmpty,
            emptyTitle: "No Sections",
            emptySystemImage: "list.bullet.rectangle",
            emptyMessage: isEditable ? "Add a section to get started." : "This protocol has no sections."
        ) {
            ForEach(Array(sections.enumerated()), id: \.element.clientID) { index, section in
                sectionRowLabel(section, number: index + 1)
                    .tag(section.clientID)
                    .accessibilityIdentifier("sectionRow_\(section.clientID)")
            }
        }
    }

    private func sectionRowLabel(_ section: CachedProtocolSection, number: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sectionTitle(section))
                Text("\(section.steps.count) step\(section.steps.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(number)")
                .font(.caption.bold())
                .padding(6)
                .background(Circle().fill(.secondary.opacity(0.2)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func sectionDetailContent(_ section: CachedProtocolSection) -> some View {
        VStack(spacing: 0) {
            ExplorerList(
                isEmpty: section.steps.isEmpty,
                emptyTitle: "No Steps",
                emptySystemImage: "list.number",
                emptyMessage: isEditable ? "Add a step to get started." : "This section has no steps.",
                accessibilityIdentifier: "stepList"
            ) {
                ForEach(section.steps.sorted(by: { $0.order < $1.order })) { step in
                    Button {
                        stepDetailTarget = step.clientID
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HTMLText(html: StepTemplateRenderer.render(stepDescription: step.stepDescription, reagents: stepReagents(for: step)))
                            if let durationLabel = stepDurationLabel(step) {
                                Text(durationLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stepRow_\(step.clientID)")
                }
                .onDelete { offsets in
                    let sortedSteps = section.steps.sorted { $0.order < $1.order }
                    Task { await deleteSteps(at: offsets, from: sortedSteps) }
                }
            }
            if isEditable {
                Divider()
                HStack(spacing: 12) {
                    Button {
                        newStepTargetSection = section
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addStepButton")

                    Button {
                        renameSectionTarget = section
                    } label: {
                        Label("Edit Section", systemImage: "pencil")
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
                .padding()
                .padding(.bottom, 80)
            }
        }
        .navigationTitle(sectionTitle(section))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            if isOwner {
                ToolbarItem {
                    Button {
                        isShowingAccessSheet = true
                    } label: {
                        Label("Manage Access", systemImage: "person.2.badge.gearshape")
                    }
                    .accessibilityIdentifier("manageProtocolAccessButton")
                }
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
            .accessibilityIdentifier("startProtocolSessionButton")
        }
        if PlatformWindowPreference.prefersSeparateWindow {
            ToolbarItem {
                Button {
                    openWindow(id: "protocol-detail-window", value: ProtocolDetailWindowID(namespaceID: namespaceID, protocolClientID: protocolModel.clientID))
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
        if let protocolServerID = protocolModel.serverID {
            ToolbarItem {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export as HTML", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportProtocolButton_\(protocolServerID)")
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
                    .accessibilityIdentifier("exportProtocolButton_\(protocolServerID)")
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

    private func addSection() async {
        let description = "New Section \(sections.count + 1)"
        let order = sections.count
        let section = CachedProtocolSection(sectionDescription: description, order: order, protocolModel: protocolModel)
        modelContext.insert(section)
        try? modelContext.save()
        selectedSectionID = section.clientID

        guard canAuthorOnline else { return }
        let clientID = section.clientID
        let services = appSession.makeSyncServices()
        do {
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
