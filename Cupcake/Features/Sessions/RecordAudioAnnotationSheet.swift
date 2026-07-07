import AVFoundation
import CupcakeNetworking
import CupcakeTranscription
import SwiftUI
import Translation

/// A simple horizontal level bar reflecting live mic input, updated by `AudioRecorder.audioLevel`.
struct AudioLevelMeterView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    .frame(width: geometry.size.width * CGFloat(level))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 8)
        .accessibilityIdentifier("audioLevelMeter")
    }
}

struct RecordAudioAnnotationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSaveLocally: (URL, String?, String?, String?) async throws -> Void
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
    @State private var onDeviceTranscriptionUnavailable = false
    #if os(iOS)
    @State private var availableInputs: [AVAudioSessionPortDescription] = []
    @State private var selectedInputUID: String?
    #endif

    private var canSave: Bool {
        recorder.recordedFileURL != nil && !isTranscribing && !isSaving
    }

    /// The bare language code (e.g. `en`), without a regional variant.
    private var baseLanguageCode: String {
        Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? localeIdentifier
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
                #if os(iOS)
                if !availableInputs.isEmpty {
                    Section("Microphone") {
                        Picker("Microphone", selection: $selectedInputUID) {
                            ForEach(availableInputs, id: \.uid) { input in
                                Text(input.portName).tag(Optional(input.uid))
                            }
                        }
                        .disabled(recorder.isRecording)
                        .onChange(of: selectedInputUID) { _, newValue in
                            recorder.setPreferredInput(availableInputs.first(where: { $0.uid == newValue }))
                        }
                    }
                }
                #endif
                Section("Recording") {
                    if recorder.isRecording {
                        AudioLevelMeterView(level: recorder.audioLevel)
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
                if onDeviceTranscriptionUnavailable {
                    Section {
                        Text("This device couldn't transcribe the recording. It'll be transcribed automatically once uploaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("transcriptionUnavailableNote")
                    }
                }
                if !transcript.isEmpty {
                    Section("Transcript") {
                        Text(transcript)
                            .accessibilityIdentifier("audioTranscriptText")
                        if baseLanguageCode != "en", translatedText.isEmpty {
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
        #if os(iOS)
        .onAppear {
            availableInputs = recorder.availableInputs()
            selectedInputUID = recorder.preferredInput()?.uid
        }
        #endif
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
        onDeviceTranscriptionUnavailable = false
        do {
            try recorder.startRecording()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    /// On-device transcription is best-effort; failure saves untranscribed with a calm inline note, not a blocking alert.
    private func stopAndTranscribe() {
        recorder.stopRecording()
        guard let fileURL = recorder.recordedFileURL else { return }
        isTranscribing = true
        onDeviceTranscriptionUnavailable = false
        Task {
            defer { isTranscribing = false }
            do {
                let result = try await SpeechTranscriber.transcribe(fileURL: fileURL, localeIdentifier: localeIdentifier)
                transcript = result.text
                transcriptSegments = result.segments
            } catch {
                onDeviceTranscriptionUnavailable = true
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
            try await onSaveLocally(fileURL, vttTranscription, vttTranscription == nil ? nil : baseLanguageCode, vttTranslation)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
