import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import PhotosUI
import SwiftData
import SwiftUI

struct PhotoAnnotationButton: View {
    let label: String
    let onPick: (Data) -> Void

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label(label, systemImage: "photo")
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    onPick(data)
                }
                pickerItem = nil
            }
        }
    }
}

struct VideoAnnotationButton: View {
    let label: String
    let onPick: (Data, String) -> Void

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickerItem, matching: .videos) {
            Label(label, systemImage: "video")
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    let fileExtension = newValue.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
                    onPick(data, fileExtension)
                }
                pickerItem = nil
            }
        }
    }
}

struct SessionDetailWindowID: Codable, Hashable {
    let sessionClientID: UUID
}

struct SessionDetailWindowContent: View {
    let windowID: SessionDetailWindowID?

    @Query private var sessions: [CachedSession]
    @Query private var protocols: [CachedProtocol]

    private var session: CachedSession? {
        guard let windowID else { return nil }
        return sessions.first { $0.clientID == windowID.sessionClientID }
    }

    private var attachedProtocols: [CachedProtocol] {
        guard let session else { return [] }
        return session.protocolClientIDs.compactMap { clientID in
            protocols.first { $0.clientID == clientID }
        }
    }

    var body: some View {
        if let windowID {
            NavigationStack {
                SessionDetailView(sessionClientID: windowID.sessionClientID, protocols: attachedProtocols)
            }
        } else {
            ContentUnavailableView("Session Not Found", systemImage: "questionmark.square.dashed")
        }
    }
}

struct StepSessionWindowID: Codable, Hashable {
    let sessionClientID: UUID
    let stepClientID: UUID
}

struct StepSessionWindowContent: View {
    let windowID: StepSessionWindowID?

    @Query private var sessions: [CachedSession]
    @Query private var protocols: [CachedProtocol]

    private var session: CachedSession? {
        guard let windowID else { return nil }
        return sessions.first { $0.clientID == windowID.sessionClientID }
    }

    private var attachedProtocols: [CachedProtocol] {
        guard let session else { return [] }
        return session.protocolClientIDs.compactMap { clientID in
            protocols.first { $0.clientID == clientID }
        }
    }

    var body: some View {
        if let windowID {
            NavigationStack {
                SessionDetailView(
                    sessionClientID: windowID.sessionClientID,
                    protocols: attachedProtocols,
                    focusedStepClientID: windowID.stepClientID
                )
            }
        } else {
            ContentUnavailableView("Step Not Found", systemImage: "questionmark.square.dashed")
        }
    }
}

struct SessionDetailView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    let sessionClientID: UUID
    let protocols: [CachedProtocol]
    var highlightAnnotationServerID: Int64? = nil

    @State private var highlightedAnnotationServerID: Int64?
    @State private var isProtocolMode: Bool
    @State private var selectedProtocolIndex = 0

    @Query private var allStepAnnotations: [CachedStepAnnotation]
    @Query private var allSessionAnnotations: [CachedSessionAnnotation]
    @Query private var sessions: [CachedSession]
    @Query private var instrumentUsages: [CachedInstrumentUsage]
    @Query private var allStepReagents: [CachedStepReagent]
    @Query private var allReagents: [CachedReagent]
    @Query private var allStepVariations: [CachedStepVariation]
    @Query private var allTimeKeepers: [CachedTimeKeeper]
    @Query private var allSteps: [CachedProtocolStep]

    @State private var annotationTargetStep: CachedProtocolStep?
    @State private var isShowingSessionAnnotationSheet = false
    @State private var variationTargetStep: CachedProtocolStep?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var hideScratched = false
    @State private var isShowingEditSheet = false
    @State private var isDeleting = false

    var focusedStepClientID: UUID? = nil

    init(sessionClientID: UUID, protocols: [CachedProtocol], highlightAnnotationServerID: Int64? = nil, focusedStepClientID: UUID? = nil) {
        self.sessionClientID = sessionClientID
        self.protocols = protocols
        self.highlightAnnotationServerID = highlightAnnotationServerID
        self.focusedStepClientID = focusedStepClientID
        self._isProtocolMode = State(initialValue: focusedStepClientID != nil || !protocols.isEmpty)
    }

    private var currentSession: CachedSession? {
        sessions.first { $0.clientID == sessionClientID }
    }

    private var currentProtocol: CachedProtocol? {
        guard protocols.indices.contains(selectedProtocolIndex) else { return protocols.first }
        return protocols[selectedProtocolIndex]
    }

    private var sessionAnnotations: [CachedSessionAnnotation] {
        allSessionAnnotations
            .filter { $0.sessionClientID == sessionClientID }
            .filter { !hideScratched || !$0.scratched }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var sessionServerID: Int64? {
        sessions.first(where: { $0.clientID == sessionClientID })?.serverID
    }

    private func rowHighlightColor(for annotationServerID: Int64?) -> Color? {
        guard let highlightedAnnotationServerID, annotationServerID == highlightedAnnotationServerID else { return nil }
        return Color.accentColor.opacity(0.25)
    }

    private func scratchActionTitle(scratched: Bool) -> String { scratched ? "Unscratch" : "Scratch" }
    private func scratchActionIcon(scratched: Bool) -> String { scratched ? "arrow.uturn.backward" : "eraser" }

    private func deepLinkURL(annotationServerID: Int64?) -> URL? {
        guard let sessionServerID, let annotationServerID else { return nil }
        var components = URLComponents()
        components.scheme = "cupcake"
        components.host = "annotation"
        components.queryItems = [
            URLQueryItem(name: "session", value: String(sessionServerID)),
            URLQueryItem(name: "id", value: String(annotationServerID)),
        ]
        return components.url
    }

    private var steps: [CachedProtocolStep] {
        if let focusedStepClientID {
            return allSteps.filter { $0.clientID == focusedStepClientID }
        }
        guard let currentProtocol else { return [] }
        return currentProtocol.sections
            .sorted { $0.order < $1.order }
            .flatMap { $0.steps.sorted { $0.order < $1.order } }
    }

    private func stepVariations(for step: CachedProtocolStep) -> [CachedStepVariation] {
        guard let stepServerID = step.serverID, let sessionServerID else { return [] }
        return allStepVariations.filter { $0.stepServerID == stepServerID && $0.sessionServerID == sessionServerID }
    }

    private func annotations(for step: CachedProtocolStep) -> [CachedStepAnnotation] {
        allStepAnnotations
            .filter { $0.sessionClientID == sessionClientID && $0.stepClientID == step.clientID }
            .filter { !hideScratched || !$0.scratched }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func instrumentUsage(for annotation: CachedStepAnnotation) -> CachedInstrumentUsage? {
        guard let usageServerID = annotation.instrumentUsageServerID else { return nil }
        return instrumentUsages.first(where: { $0.serverID == usageServerID })
    }

    private func stepReagents(for step: CachedProtocolStep) -> [(stepReagent: CachedStepReagent, reagent: CachedReagent)] {
        allStepReagents
            .filter { $0.stepClientID == step.clientID }
            .compactMap { stepReagent in
                guard let reagent = allReagents.first(where: { $0.clientID == stepReagent.reagentClientID }) else { return nil }
                return (stepReagent, reagent)
            }
    }

    @ViewBuilder
    private func bookingAnnotationRow(_ annotation: CachedStepAnnotation) -> some View {
        if let usage = instrumentUsage(for: annotation) {
            VStack(alignment: .leading, spacing: 2) {
                Label(usage.instrumentName, systemImage: "wrench.and.screwdriver")
                Text(HumanReadableTime.formatAbsolute(usage.timeStarted) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label(annotation.annotationText, systemImage: "wrench.and.screwdriver")
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        List {
            if !isProtocolMode, focusedStepClientID == nil {
            Section("Session Notes") {
                ForEach(sessionAnnotations) { annotation in
                    Group {
                        if annotation.annotationType == "image" {
                            PhotoAnnotationPreview(loadData: { try await sessionAnnotationFile(clientID: annotation.clientID) })
                        } else if annotation.annotationType == "video" {
                            VideoAnnotationPreview(
                                annotationServerID: annotation.serverID,
                                transcription: annotation.transcription,
                                refreshTranscription: annotation.serverID.map { id in { await refreshSessionTranscription(serverID: id) } },
                                loadData: { try await sessionAnnotationFile(clientID: annotation.clientID) }
                            )
                        } else if annotation.annotationType == "sketch" {
                            SketchAnnotationPreview(loadData: { try await sessionAnnotationFile(clientID: annotation.clientID) })
                        } else {
                            AudioAnnotationPreview(
                                annotationServerID: annotation.serverID,
                                transcription: annotation.transcription,
                                translation: annotation.translation,
                                language: annotation.language,
                                refreshTranscription: annotation.serverID.map { id in { await refreshSessionTranscription(serverID: id) } },
                                loadData: { try await sessionAnnotationFile(clientID: annotation.clientID) }
                            )
                        }
                    }
                    .opacity(annotation.scratched ? 0.5 : 1)
                    .listRowBackground(rowHighlightColor(for: annotation.serverID))
                    .id(annotation.serverID ?? -1)
                    .swipeActions(edge: .leading) {
                        if let shareURL = deepLinkURL(annotationServerID: annotation.serverID) {
                            ShareLink(item: shareURL) {
                                Label("Share Link", systemImage: "link")
                            }
                            .tint(.blue)
                            .accessibilityIdentifier("shareSessionAnnotationLinkButton")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deleteSessionAnnotation(annotation) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("deleteSessionAnnotationButton")
                        Button {
                            Task { await toggleSessionAnnotationScratched(annotation) }
                        } label: {
                            Label(scratchActionTitle(scratched: annotation.scratched), systemImage: scratchActionIcon(scratched: annotation.scratched))
                        }
                        .tint(.orange)
                        .accessibilityIdentifier("scratchSessionAnnotationButton")
                    }
                }
                Button("Add Annotation…") {
                    isShowingSessionAnnotationSheet = true
                }
                .accessibilityIdentifier("addSessionAnnotationButton")
                if let sessionServerID {
                    NavigationLink {
                        SessionAnnotationFoldersView(sessionServerID: sessionServerID)
                    } label: {
                        Label("Browse Folders", systemImage: "folder")
                    }
                    .accessibilityIdentifier("browseSessionAnnotationFoldersLink")
                }
            }
            }
            if isProtocolMode {
            ForEach(steps) { step in
                Section {
                    ForEach(annotations(for: step)) { annotation in
                        Group {
                            if annotation.annotationType == "audio" {
                                AudioAnnotationPreview(
                                    annotationServerID: annotation.serverID,
                                    transcription: annotation.transcription,
                                    translation: annotation.translation,
                                    language: annotation.language,
                                    refreshTranscription: annotation.serverID.map { id in { await refreshStepTranscription(serverID: id) } },
                                    loadData: { try await stepAnnotationFile(clientID: annotation.clientID) }
                                )
                            } else if annotation.annotationType == "image" {
                                PhotoAnnotationPreview(loadData: { try await stepAnnotationFile(clientID: annotation.clientID) })
                            } else if annotation.annotationType == "video" {
                                VideoAnnotationPreview(
                                    annotationServerID: annotation.serverID,
                                    transcription: annotation.transcription,
                                    refreshTranscription: annotation.serverID.map { id in { await refreshStepTranscription(serverID: id) } },
                                    loadData: { try await stepAnnotationFile(clientID: annotation.clientID) }
                                )
                            } else if annotation.annotationType == "sketch" {
                                SketchAnnotationPreview(loadData: { try await stepAnnotationFile(clientID: annotation.clientID) })
                            } else if annotation.annotationType == "calculator" {
                                CalculatorAnnotationPreview(annotationText: annotation.annotationText)
                            } else if annotation.annotationType == "mcalculator" {
                                MolarityCalculatorAnnotationPreview(annotationText: annotation.annotationText)
                            } else if annotation.annotationType == "booking" {
                                bookingAnnotationRow(annotation)
                            } else {
                                HTMLText(html: annotation.annotationText)
                            }
                        }
                        .opacity(annotation.scratched ? 0.5 : 1)
                        .listRowBackground(rowHighlightColor(for: annotation.serverID))
                        .id(annotation.serverID ?? -1)
                        .swipeActions(edge: .leading) {
                            if let shareURL = deepLinkURL(annotationServerID: annotation.serverID) {
                                ShareLink(item: shareURL) {
                                    Label("Share Link", systemImage: "link")
                                }
                                .tint(.blue)
                                .accessibilityIdentifier("shareStepAnnotationLinkButton")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await deleteStepAnnotation(annotation) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityIdentifier("deleteStepAnnotationButton")
                            Button {
                                Task { await toggleStepAnnotationScratched(annotation) }
                            } label: {
                                Label(scratchActionTitle(scratched: annotation.scratched), systemImage: scratchActionIcon(scratched: annotation.scratched))
                            }
                            .tint(.orange)
                            .accessibilityIdentifier("scratchStepAnnotationButton")
                        }
                    }
                    ForEach(stepVariations(for: step)) { variation in
                        Text("Variation: \(variation.variationDescription) (\(HumanReadableDuration.format(seconds: variation.variationDuration)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Add Annotation…") {
                        annotationTargetStep = step
                    }
                    .accessibilityIdentifier("addStepAnnotationButton")
                    if sessionServerID != nil, step.serverID != nil {
                        Button {
                            variationTargetStep = step
                        } label: {
                            Label("Add Variation", systemImage: "arrow.triangle.branch")
                        }
                        .accessibilityIdentifier("addVariationButton")
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            HTMLText(html: StepTemplateRenderer.render(stepDescription: step.stepDescription, reagents: stepReagents(for: step)))
                            if focusedStepClientID == nil, PlatformWindowPreference.prefersSeparateWindow {
                                Spacer()
                                Button {
                                    openWindow(id: "step-session-window", value: StepSessionWindowID(sessionClientID: sessionClientID, stepClientID: step.clientID))
                                } label: {
                                    Image(systemName: "macwindow.badge.plus")
                                }
                                .buttonStyle(.borderless)
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("Open Step in New Window")
                                .accessibilityIdentifier("openStepSessionInWindowButton_\(step.clientID)")
                            }
                        }
                        if let sessionServerID {
                            StepTimerView(sessionServerID: sessionServerID, sessionClientID: sessionClientID, step: step) {
                                await refreshTimeKeepers(sessionServerID: sessionServerID)
                            }
                        }
                    }
                }
            }
            }
        }
        .navigationTitle(focusedStepClientID == nil ? "Session" : "Step")
        .toolbar {
            if focusedStepClientID == nil, !protocols.isEmpty {
                ToolbarItem {
                    Picker("Mode", selection: $isProtocolMode) {
                        Text("Protocol").tag(true)
                        Text("Notes").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("sessionModePicker")
                }
            }
            if focusedStepClientID == nil, isProtocolMode, protocols.count > 1 {
                ToolbarItem {
                    Picker("Protocol", selection: $selectedProtocolIndex) {
                        ForEach(protocols.indices, id: \.self) { index in
                            Text(protocols[index].protocolTitle).tag(index)
                        }
                    }
                    .accessibilityIdentifier("sessionProtocolPicker")
                }
            }
            ToolbarItem {
                Toggle(isOn: $hideScratched) {
                    Label("Hide Scratched", systemImage: hideScratched ? "eye.slash.fill" : "eye.slash")
                }
                .toggleStyle(.button)
                .accessibilityIdentifier("hideScratchedToggle")
            }
            if focusedStepClientID == nil, PlatformWindowPreference.prefersSeparateWindow {
                ToolbarItem {
                    Button {
                        openWindow(id: "session-detail-window", value: SessionDetailWindowID(sessionClientID: sessionClientID))
                    } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                    .accessibilityIdentifier("openSessionInWindowButton")
                }
            }
            if currentSession?.serverID != nil {
                ToolbarItem {
                    Button {
                        isShowingEditSheet = true
                    } label: {
                        Label("Edit Session", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("editSessionButton")
                }
                ToolbarItem {
                    Button(role: .destructive) {
                        Task { await deleteSession() }
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Label("Delete Session", systemImage: "trash")
                        }
                    }
                    .disabled(isDeleting)
                    .accessibilityIdentifier("deleteSessionButton")
                }
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let currentSession {
                EditSessionSheet(session: currentSession)
            }
        }
        .sheet(item: $annotationTargetStep) { step in
            let onSaveStepAudio: (URL, String?, String?, String?) async throws -> Void = { fileURL, transcription, language, translation in
                let services = appSession.makeSyncServices()
                let clientID = try await services.stepAnnotationSync.createAudioAnnotation(
                    sessionClientID: sessionClientID,
                    stepClientID: step.clientID,
                    recordedFileURL: fileURL,
                    transcription: transcription,
                    language: language,
                    translation: translation
                )
                Task { await syncStepAudioAnnotation(clientID: clientID) }
            }
            let onSaveStepVideo: (URL, String?, String?, String?) async throws -> Void = { fileURL, transcription, language, translation in
                let services = appSession.makeSyncServices()
                let clientID = try await services.stepAnnotationSync.createFileAnnotation(
                    sessionClientID: sessionClientID,
                    stepClientID: step.clientID,
                    fileURL: fileURL,
                    fileExtension: "mov",
                    annotationType: "video",
                    transcription: transcription,
                    language: language,
                    translation: translation
                )
                Task { await syncStepVideoAnnotation(clientID: clientID) }
            }
            AddAnnotationSheet(
                scope: .step(step),
                sessionServerID: sessionServerID,
                sessionClientID: sessionClientID,
                onSaveText: { text in Task { await saveAnnotation(step: step, text: text) } },
                onPickPhoto: { data in Task { await handleStepPhoto(step: step, data: data) } },
                onPickVideo: { data, fileExtension in Task { await handleStepVideo(step: step, data: data, fileExtension: fileExtension) } },
                onSaveSketch: { data in Task { await handleStepSketch(step: step, data: data) } },
                onSaveAudio: onSaveStepAudio,
                onSaveVideo: onSaveStepVideo,
                onSaveCalculator: { data in Task { await handleStepCalculator(step: step, data: data) } },
                onSaveMolarityCalculator: { data in Task { await handleStepMolarityCalculator(step: step, data: data) } }
            )
        }
        .sheet(isPresented: $isShowingSessionAnnotationSheet) {
            let onSaveSessionAudio: (URL, String?, String?, String?) async throws -> Void = { fileURL, transcription, language, translation in
                let services = appSession.makeSyncServices()
                let clientID = try await services.sessionAnnotationSync.createAudioAnnotation(
                    sessionClientID: sessionClientID,
                    recordedFileURL: fileURL,
                    transcription: transcription,
                    language: language,
                    translation: translation
                )
                Task { await syncSessionAudioAnnotation(clientID: clientID) }
            }
            let onSaveSessionVideo: (URL, String?, String?, String?) async throws -> Void = { fileURL, transcription, language, translation in
                let services = appSession.makeSyncServices()
                let clientID = try await services.sessionAnnotationSync.createFileAnnotation(
                    sessionClientID: sessionClientID,
                    fileURL: fileURL,
                    fileExtension: "mov",
                    annotationType: "video",
                    transcription: transcription,
                    language: language,
                    translation: translation
                )
                Task { await syncSessionVideoAnnotation(clientID: clientID) }
            }
            AddAnnotationSheet(
                scope: .session,
                sessionServerID: sessionServerID,
                sessionClientID: sessionClientID,
                onSaveText: { _ in },
                onPickPhoto: { data in Task { await handleSessionPhoto(data: data) } },
                onPickVideo: { data, fileExtension in Task { await handleSessionVideo(data: data, fileExtension: fileExtension) } },
                onSaveSketch: { data in Task { await handleSessionSketch(data: data) } },
                onSaveAudio: onSaveSessionAudio,
                onSaveVideo: onSaveSessionVideo,
                onSaveCalculator: { _ in },
                onSaveMolarityCalculator: { _ in }
            )
        }
        .sheet(item: $variationTargetStep, onDismiss: {
            Task { await refetchStepVariations() }
        }) { step in
            if let stepServerID = step.serverID, let sessionServerID {
                AddStepVariationSheet(stepServerID: stepServerID, sessionServerID: sessionServerID)
            }
        }
        .alert("Couldn't save annotation", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: highlightAnnotationServerID) {
            guard let highlightAnnotationServerID else { return }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation {
                scrollProxy.scrollTo(highlightAnnotationServerID as Int64, anchor: .center)
            }
            highlightedAnnotationServerID = highlightAnnotationServerID
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                highlightedAnnotationServerID = nil
            }
        }
        .task {
            guard allStepAnnotations.contains(where: { $0.annotationType == "booking" && $0.instrumentUsageServerID != nil }) else { return }
            try? await appSession.makeSyncServices().instrumentSync.refetchInstrumentUsage()
        }
        .task(id: sessionServerID) {
            guard let sessionServerID else { return }
            await refreshTimeKeepers(sessionServerID: sessionServerID)
            for await event in await appSession.timeKeeperEvents() {
                guard event.sessionServerID == sessionServerID else { continue }
                await refreshTimeKeepers(sessionServerID: sessionServerID)
            }
        }
        .task(id: "\(sessionServerID ?? -1)_\(selectedProtocolIndex)") {
            await refetchStepVariations()
        }
        }
    }

    private func refetchStepVariations() async {
        guard let sessionServerID else { return }
        for step in steps {
            guard let stepServerID = step.serverID else { continue }
            try? await appSession.makeSyncServices().stepVariationSync.refetch(stepServerID: stepServerID, sessionServerID: sessionServerID)
        }
    }

    private func refreshTimeKeepers(sessionServerID: Int64) async {
        guard let dtos = try? await appSession.makeSyncServices().timeKeeperSync.fetchTimeKeepers(sessionServerID: sessionServerID) else { return }
        for dto in dtos {
            let stepClientID = dto.step.flatMap { stepServerID in allSteps.first(where: { $0.serverID == stepServerID })?.clientID }
            if let existing = allTimeKeepers.first(where: { $0.serverID == dto.id }) {
                existing.started = dto.started
                existing.startTime = dto.startTime
                existing.currentDuration = dto.currentDuration
                existing.originalDuration = dto.originalDuration
            } else {
                modelContext.insert(CachedTimeKeeper(
                    serverID: dto.id,
                    sessionClientID: sessionClientID,
                    stepClientID: stepClientID,
                    started: dto.started,
                    startTime: dto.startTime,
                    currentDuration: dto.currentDuration,
                    originalDuration: dto.originalDuration
                ))
            }
        }
        try? modelContext.save()
    }

    private func stepAnnotationFile(clientID: UUID) async throws -> (data: Data, suggestedFilename: String?) {
        try await appSession.makeSyncServices().stepAnnotationSync.downloadFile(clientID: clientID)
    }

    private func sessionAnnotationFile(clientID: UUID) async throws -> (data: Data, suggestedFilename: String?) {
        try await appSession.makeSyncServices().sessionAnnotationSync.downloadFile(clientID: clientID)
    }

    private func refreshStepTranscription(serverID: Int64) async {
        try? await appSession.makeSyncServices().stepAnnotationSync.refreshTranscription(serverID: serverID)
    }

    private func refreshSessionTranscription(serverID: Int64) async {
        try? await appSession.makeSyncServices().sessionAnnotationSync.refreshTranscription(serverID: serverID)
    }

    private func deleteSession() async {
        guard let serverID = currentSession?.serverID else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await appSession.makeSyncServices().sessionSync.delete(serverID: serverID)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func handleStepPhoto(step: CachedProtocolStep, data: Data) async {
        let services = appSession.makeSyncServices()
        guard let clientID = try? await services.stepAnnotationSync.createImageAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: step.clientID,
            imageData: data
        ) else { return }
        await syncStepImageAnnotation(clientID: clientID)
    }

    private func handleSessionPhoto(data: Data) async {
        let services = appSession.makeSyncServices()
        guard let clientID = try? await services.sessionAnnotationSync.createImageAnnotation(
            sessionClientID: sessionClientID,
            imageData: data
        ) else { return }
        await syncSessionImageAnnotation(clientID: clientID)
    }

    private func syncStepImageAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.stepAnnotationSync.syncLocallyCreatedImageAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateStepImageAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateStepImageAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func syncSessionImageAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.sessionAnnotationSync.syncLocallyCreatedImageAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateSessionImageAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateSessionImageAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func handleStepVideo(step: CachedProtocolStep, data: Data, fileExtension: String) async {
        let services = appSession.makeSyncServices()
        guard let clientID = try? await services.stepAnnotationSync.createVideoAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: step.clientID,
            videoData: data,
            fileExtension: fileExtension
        ) else { return }
        await syncStepVideoAnnotation(clientID: clientID)
    }

    private func handleSessionVideo(data: Data, fileExtension: String) async {
        let services = appSession.makeSyncServices()
        guard let clientID = try? await services.sessionAnnotationSync.createVideoAnnotation(
            sessionClientID: sessionClientID,
            videoData: data,
            fileExtension: fileExtension
        ) else { return }
        await syncSessionVideoAnnotation(clientID: clientID)
    }

    private func syncStepVideoAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.stepAnnotationSync.syncLocallyCreatedVideoAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateStepVideoAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateStepVideoAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func syncSessionVideoAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.sessionAnnotationSync.syncLocallyCreatedVideoAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateSessionVideoAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateSessionVideoAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func handleStepSketch(step: CachedProtocolStep, data: Data) async {
        let services = appSession.makeSyncServices()
        guard let clientID = try? await services.stepAnnotationSync.createSketchAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: step.clientID,
            sketchData: data
        ) else { return }
        await syncStepSketchAnnotation(clientID: clientID)
    }

    private func handleSessionSketch(data: Data) async {
        let services = appSession.makeSyncServices()
        guard let clientID = try? await services.sessionAnnotationSync.createSketchAnnotation(
            sessionClientID: sessionClientID,
            sketchData: data
        ) else { return }
        await syncSessionSketchAnnotation(clientID: clientID)
    }

    private func syncStepSketchAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.stepAnnotationSync.syncLocallyCreatedSketchAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateStepSketchAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateStepSketchAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func syncSessionSketchAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.sessionAnnotationSync.syncLocallyCreatedSketchAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateSessionSketchAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateSessionSketchAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func handleStepCalculator(step: CachedProtocolStep, data: Data) async {
        guard let historyJSON = String(data: data, encoding: .utf8) else { return }
        let services = appSession.makeSyncServices()
        guard let clientID = try? await services.stepAnnotationSync.createCalculatorAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: step.clientID,
            historyJSON: historyJSON
        ) else { return }
        await syncStepCalculatorAnnotation(clientID: clientID)
    }

    private func syncStepCalculatorAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.stepAnnotationSync.syncLocallyCreatedCalculatorAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateTextAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateTextAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func handleStepMolarityCalculator(step: CachedProtocolStep, data: Data) async {
        guard let historyJSON = String(data: data, encoding: .utf8) else { return }
        let services = appSession.makeSyncServices()
        guard let clientID = try? await services.stepAnnotationSync.createMolarityCalculatorAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: step.clientID,
            historyJSON: historyJSON
        ) else { return }
        await syncStepMolarityCalculatorAnnotation(clientID: clientID)
    }

    private func syncStepMolarityCalculatorAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.stepAnnotationSync.syncLocallyCreatedMolarityCalculatorAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateTextAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateTextAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func toggleSessionAnnotationScratched(_ annotation: CachedSessionAnnotation) async {
        do {
            try await appSession.makeSyncServices().sessionAnnotationSync.setScratched(clientID: annotation.clientID, scratched: !annotation.scratched)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func deleteSessionAnnotation(_ annotation: CachedSessionAnnotation) async {
        do {
            try await appSession.makeSyncServices().sessionAnnotationSync.deleteAnnotation(clientID: annotation.clientID)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func toggleStepAnnotationScratched(_ annotation: CachedStepAnnotation) async {
        do {
            try await appSession.makeSyncServices().stepAnnotationSync.setScratched(clientID: annotation.clientID, scratched: !annotation.scratched)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func deleteStepAnnotation(_ annotation: CachedStepAnnotation) async {
        do {
            try await appSession.makeSyncServices().stepAnnotationSync.deleteAnnotation(clientID: annotation.clientID)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func saveAnnotation(step: CachedProtocolStep, text: String) async {
        isSaving = true
        defer { isSaving = false }

        let services = appSession.makeSyncServices()
        let clientID = try? await services.stepAnnotationSync.createTextAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: step.clientID,
            text: text
        )

        guard appSession.isAuthenticated, let clientID else { return }
        do {
            try await services.stepAnnotationSync.syncLocallyCreatedTextAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateTextAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateTextAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func syncStepAudioAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.stepAnnotationSync.syncLocallyCreatedAudioAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateStepAudioAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateStepAudioAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }

    private func syncSessionAudioAnnotation(clientID: UUID) async {
        guard appSession.isAuthenticated else { return }
        let services = appSession.makeSyncServices()
        do {
            try await services.sessionAnnotationSync.syncLocallyCreatedAudioAnnotation(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateSessionAudioAnnotation(clientID: clientID)
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateSessionAudioAnnotation(clientID: clientID)
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }
}
