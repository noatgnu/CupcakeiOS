import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import CupcakeTranscription
import SwiftData
import SwiftUI

struct SessionDetailView: View {
    @Environment(AppSession.self) private var appSession
    let sessionClientID: UUID
    let protocolModel: CachedProtocol

    @Query private var allStepAnnotations: [CachedStepAnnotation]
    @Query private var sessions: [CachedSession]

    @State private var selectedStep: CachedProtocolStep?
    @State private var annotationText = ""
    @State private var recordingStep: CachedProtocolStep?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var sessionServerID: Int64? {
        sessions.first(where: { $0.clientID == sessionClientID })?.serverID
    }

    private var steps: [CachedProtocolStep] {
        protocolModel.sections
            .sorted { $0.order < $1.order }
            .flatMap { $0.steps.sorted { $0.order < $1.order } }
    }

    private func annotations(for step: CachedProtocolStep) -> [CachedStepAnnotation] {
        allStepAnnotations.filter { $0.sessionClientID == sessionClientID && $0.stepClientID == step.clientID }
    }

    var body: some View {
        List {
            ForEach(steps) { step in
                Section {
                    ForEach(annotations(for: step)) { annotation in
                        if annotation.annotationType == "audio" {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(annotation.transcription.map(WebVTTFormatter.extractPlainText) ?? "Audio note", systemImage: "waveform")
                                if let translation = annotation.translation {
                                    Text(WebVTTFormatter.extractPlainText(from: translation))
                                        .font(.caption)
                                } else if let language = annotation.language {
                                    Text(language)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HTMLText(html: annotation.annotationText)
                        }
                    }
                    Button("Add note…") {
                        selectedStep = step
                    }
                    .accessibilityIdentifier("addNoteButton")
                    if sessionServerID != nil, step.serverID != nil {
                        Button("Record Audio Note…") {
                            recordingStep = step
                        }
                        .accessibilityIdentifier("recordAudioNoteButton")
                    }
                } header: {
                    HTMLText(html: step.stepDescription)
                }
            }
        }
        .navigationTitle("Session")
        .sheet(item: $selectedStep) { step in
            NavigationStack {
                Form {
                    TextField("Note", text: $annotationText, axis: .vertical)
                        .accessibilityIdentifier("noteTextField")
                }
                .navigationTitle(HTMLText.plainText(from: step.stepDescription))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            selectedStep = nil
                            annotationText = ""
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await saveAnnotation(step: step) }
                        }
                        .disabled(isSaving || annotationText.isEmpty)
                        .accessibilityIdentifier("saveNoteButton")
                    }
                }
            }
            .frame(minWidth: 320, minHeight: 240)
        }
        .sheet(item: $recordingStep) { step in
            if let sessionServerID, let stepServerID = step.serverID {
                RecordAudioAnnotationSheet(
                    sessionClientID: sessionClientID,
                    sessionServerID: sessionServerID,
                    stepClientID: step.clientID,
                    stepServerID: stepServerID
                ) {
                    recordingStep = nil
                }
            }
        }
        .alert("Couldn't save annotation", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Always created locally first (so nothing is lost or blocked on the network, and the sheet
    /// dismisses immediately), then synced right away when signed in — a genuine unreachability
    /// failure queues it in the outbox instead of erroring out, same create-locally-then-
    /// sync-or-queue pattern as protocol/section/step/session/step-reagent creation.
    private func saveAnnotation(step: CachedProtocolStep) async {
        isSaving = true
        defer { isSaving = false }

        let services = appSession.makeSyncServices()
        let clientID = try? await services.stepAnnotationSync.createTextAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: step.clientID,
            text: annotationText
        )
        annotationText = ""
        selectedStep = nil

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
}
