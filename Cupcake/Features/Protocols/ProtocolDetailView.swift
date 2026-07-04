import CupcakeModels
import CupcakeSync
import SwiftData
import SwiftUI

struct ProtocolDetailView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
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

    private var sections: [CachedProtocolSection] {
        protocolModel.sections.sorted { $0.order < $1.order }
    }

    /// Governs whether starting a session, or adding a section/step/reagent, goes through the
    /// network (protocol is actually on the server and we're signed in) or is created directly
    /// in the local store instead (locally-created protocol, or standalone/offline mode). Same
    /// UI, same result either way — only where the write lands differs.
    private var canAuthorOnline: Bool {
        protocolModel.serverID != nil && appSession.isAuthenticated
    }

    /// A protocol this app authored (whether it ever synced or not) stays editable; one fetched
    /// as someone else's read-only reference data (§3) doesn't. Not `serverID == nil` — a
    /// protocol created online by this app still has a real `serverID` but should stay editable
    /// (see `CachedProtocol.isLocallyAuthored`'s doc comment for why the two aren't the same
    /// thing).
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

    /// Matches the reference web app's display of `scaledQuantity = quantity * scalableFactor`
    /// (`ccrv/serializers.py:731-734`) for scalable reagents.
    private func reagentDisplayText(_ entry: (stepReagent: CachedStepReagent, reagent: CachedReagent)) -> String {
        let base = "\(entry.reagent.name): \(entry.stepReagent.quantity.formatted()) \(entry.reagent.unit)"
        guard entry.stepReagent.scalable else { return base }
        let scaled = entry.stepReagent.quantity * entry.stepReagent.scalableFactor
        return "\(base) — ×\(entry.stepReagent.scalableFactor.formatted()) = \(scaled.formatted()) \(entry.reagent.unit)"
    }

    /// Stored durations are seconds (see `CachedProtocolStep.stepDuration`'s doc comment) —
    /// displayed here in minutes, rounded up, since sub-minute precision isn't meaningful for a
    /// lab protocol's step timing.
    private func minutes(fromSeconds seconds: Int) -> Int {
        Int((Double(seconds) / 60.0).rounded(.up))
    }

    private func sectionTitle(_ section: CachedProtocolSection) -> String {
        let base = section.sectionDescription ?? "Untitled Section"
        guard let duration = section.sectionDuration else { return base }
        return "\(base) (\(minutes(fromSeconds: duration)) min)"
    }

    private func stepTitle(_ step: CachedProtocolStep) -> String {
        guard let duration = step.stepDuration else { return step.stepDescription }
        return "\(step.stepDescription) (\(minutes(fromSeconds: duration)) min)"
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(sectionTitle(section)) {
                    ForEach(section.steps.sorted(by: { $0.order < $1.order })) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stepTitle(step))
                            ForEach(stepReagents(for: step), id: \.stepReagent.clientID) { entry in
                                Text(reagentDisplayText(entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                reagentAttachmentTargetStep = step
                            } label: {
                                Label("Attach Reagent", systemImage: "eyedropper")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("attachReagentButton")
                        }
                    }
                    if isEditable {
                        // Vertically stacked, not an HStack — two labeled buttons side by side
                        // can overflow horizontally on a narrow iPhone width, leaving one
                        // unhittable even after XCUITest's own scroll-to-visible attempt
                        // (confirmed: "Add Step" became unhittable once "Rename Section" grew the
                        // row wider than the screen).
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
                        }
                    }
                }
            }
        }
        .navigationTitle(protocolModel.protocolTitle)
        .toolbar {
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
        }
        .navigationDestination(item: $createdSessionClientID) { sessionClientID in
            SessionDetailView(sessionClientID: sessionClientID, protocolModel: protocolModel)
        }
        .sheet(item: $renameSectionTarget) { section in
            AddTextSheet(title: "Rename Section", prompt: "Section name", initialText: section.sectionDescription ?? "") { newName in
                section.sectionDescription = newName
                try? modelContext.save()
            }
        }
        .sheet(item: $newStepTargetSection) { section in
            AddStepSheet { description, duration in
                Task { await addStep(description: description, duration: duration, to: section) }
            }
        }
        .sheet(item: $reagentAttachmentTargetStep) { step in
            AttachReagentSheet(step: step, canAuthorOnline: canAuthorOnline)
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

    /// Created instantly with a default name, no dialog — matches the reference web app's
    /// `createSection()` (`protocol-editor.ts:186-210`), which POSTs immediately with a
    /// `"New Section N"` placeholder name and lets the user rename afterward, rather than
    /// collecting a name upfront. Goes to the server when this protocol is online-authored
    /// (`canAuthorOnline`), else created directly in the local store — same "online when
    /// possible, else local" pattern as `startSession`.
    private func addSection() async {
        let description = "New Section \(sections.count + 1)"
        let order = sections.count

        if canAuthorOnline, let protocolServerID = protocolModel.serverID {
            do {
                let services = appSession.makeSyncServices()
                try await services.protocolSync.createSection(protocolServerID: protocolServerID, description: description, duration: nil, order: order)
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        } else {
            let section = CachedProtocolSection(sectionDescription: description, order: order, protocolModel: protocolModel)
            modelContext.insert(section)
            try? modelContext.save()
        }
    }

    private func addStep(description: String, duration: Int?, to section: CachedProtocolSection) async {
        let order = section.steps.count

        if canAuthorOnline, let protocolServerID = protocolModel.serverID, let sectionServerID = section.serverID {
            do {
                let services = appSession.makeSyncServices()
                try await services.protocolSync.createStep(protocolServerID: protocolServerID, sectionServerID: sectionServerID, description: description, duration: duration, order: order)
                recomputeSectionDuration(for: section)
                try? modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        } else {
            let step = CachedProtocolStep(
                stepDescription: description,
                order: order,
                stepDuration: duration,
                section: section
            )
            modelContext.insert(step)
            recomputeSectionDuration(for: section)
            try? modelContext.save()
        }
    }

    /// A section's own duration isn't entered directly here — it's the sum of its steps'
    /// durations. This deliberately diverges from the reference web app, where section duration
    /// is an independently editable field, never computed from steps — an explicit design
    /// choice for this app's local-authoring flow, not an unverified assumption (see
    /// `CachedProtocolSection.sectionDuration`'s doc comment). `nil` (not `0`) when no step in
    /// the section has a duration set, so an unset duration doesn't display as a misleading
    /// "(0 min)".
    private func recomputeSectionDuration(for section: CachedProtocolSection) {
        let durations = section.steps.compactMap(\.stepDuration)
        section.sectionDuration = durations.isEmpty ? nil : durations.reduce(0, +)
    }

    private func startSession(name: String, enabled: Bool) async {
        isCreatingSession = true
        defer { isCreatingSession = false }

        if canAuthorOnline, let serverID = protocolModel.serverID {
            do {
                let services = appSession.makeSyncServices()
                createdSessionClientID = try await services.sessionSync.createSession(
                    name: name,
                    enabled: enabled,
                    protocolServerIDs: [serverID]
                )
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        } else {
            let session = CachedSession(
                uniqueID: nil,
                name: name,
                enabled: enabled,
                isRunning: true,
                status: "running",
                primaryProtocolClientID: protocolModel.clientID
            )
            modelContext.insert(session)
            try? modelContext.save()
            createdSessionClientID = session.clientID
        }
    }
}
