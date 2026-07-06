import CupcakeNetworking
import CupcakeSync
import CupcakeTranscription
import SwiftUI
import Translation

struct RecordAudioAnnotationSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let sessionClientID: UUID
    let sessionServerID: Int64
    let stepClientID: UUID
    let stepServerID: Int64
    let onSaved: () -> Void

    private static let commonLocales = [
        "en-US", "es-ES", "fr-FR", "de-DE", "zh-Hans", "ja-JP",
    ]

    @State private var recorder = AudioRecorder()
    @State private var localeIdentifier = Locale.current.identifier
    @State private var transcript = ""
    @State private var transcriptSegments: [TranscriptionSegment] = []
    @State private var translatedText = ""
    @State private var isTranscribing = false
    @State private var isTranslating = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var translationConfiguration: TranslationSession.Configuration?

    private var canSave: Bool {
        recorder.recordedFileURL != nil && !isTranscribing && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("Spoken Language", selection: $localeIdentifier) {
                        ForEach(Self.commonLocales, id: \.self) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale) ?? locale).tag(locale)
                        }
                    }
                    .disabled(recorder.isRecording || recorder.recordedFileURL != nil)
                    if !SpeechTranscriber.supportsOnDeviceRecognition(localeIdentifier: localeIdentifier) {
                        Text("On-device recognition isn't available for this language on this device — the server will transcribe it instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Recording") {
                    if recorder.isRecording {
                        Button("Stop Recording", role: .destructive) {
                            stopAndTranscribe()
                        }
                        .accessibilityIdentifier("stopRecordingButton")
                    } else {
                        Button(recorder.recordedFileURL == nil ? "Start Recording" : "Record Again") {
                            Task { await startRecording() }
                        }
                        .accessibilityIdentifier("startRecordingButton")
                    }
                }
                if isTranscribing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Transcribing on-device…")
                        }
                    }
                }
                if !transcript.isEmpty {
                    Section("Transcript") {
                        Text(transcript)
                            .accessibilityIdentifier("audioTranscriptText")
                        if localeIdentifier != "en-US", translatedText.isEmpty {
                            Button(isTranslating ? "Translating…" : "Translate to English") {
                                translationConfiguration = TranslationSession.Configuration(
                                    source: Locale.Language(identifier: localeIdentifier),
                                    target: Locale.Language(identifier: "en")
                                )
                            }
                            .disabled(isTranslating)
                            .accessibilityIdentifier("translateButton")
                        }
                    }
                }
                if !translatedText.isEmpty {
                    Section("English Translation") {
                        Text(translatedText)
                            .accessibilityIdentifier("audioTranslationText")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Record Audio Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveAudioAnnotationButton")
                }
            }
        }
        .frame(minWidth: 380, minHeight: 460)
        .alert("Couldn't save recording", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .translationTask(translationConfiguration) { session in
            isTranslating = true
            defer { isTranslating = false }
            do {
                let response = try await session.translate(transcript)
                translatedText = response.targetText
            } catch {
            }
        }
    }

    private func startRecording() async {
        guard await recorder.requestPermission() else {
            errorMessage = "Microphone access was denied."
            isShowingError = true
            return
        }
        transcript = ""
        translatedText = ""
        do {
            try recorder.startRecording()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func stopAndTranscribe() {
        recorder.stopRecording()
        guard let fileURL = recorder.recordedFileURL else { return }
        isTranscribing = true
        Task {
            defer { isTranscribing = false }
            do {
                let result = try await SpeechTranscriber.transcribe(fileURL: fileURL, localeIdentifier: localeIdentifier)
                transcript = result.text
                transcriptSegments = result.segments
            } catch {
                errorMessage = "On-device transcription failed: \(error.userFacingMessage)"
                isShowingError = true
            }
        }
    }

    private func save() async {
        guard let fileURL = recorder.recordedFileURL else { return }
        isSaving = true
        defer { isSaving = false }
        let vttTranscription = transcriptSegments.isEmpty ? nil : WebVTTFormatter.format(segments: transcriptSegments)
        let vttTranslation: String? = {
            guard !translatedText.isEmpty, let lastSegment = transcriptSegments.last else { return nil }
            return WebVTTFormatter.formatSingleCue(text: translatedText, duration: lastSegment.timestamp + lastSegment.duration)
        }()
        do {
            let services = appSession.makeSyncServices()
            try await services.stepAnnotationSync.uploadAudioAnnotation(
                sessionServerID: sessionServerID,
                stepServerID: stepServerID,
                sessionClientID: sessionClientID,
                stepClientID: stepClientID,
                fileURL: fileURL,
                transcription: vttTranscription,
                language: vttTranscription == nil ? nil : localeIdentifier,
                translation: vttTranslation
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
