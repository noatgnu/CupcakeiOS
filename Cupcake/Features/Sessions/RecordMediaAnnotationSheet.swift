import AVFoundation
import CupcakeNetworking
import CupcakeTranscription
import SwiftUI
import Translation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

struct CameraPreviewView: View {
    let session: AVCaptureSession

    var body: some View {
        CameraPreviewRepresentable(session: session)
            .accessibilityIdentifier("cameraPreview")
    }
}

#if os(iOS)
private struct CameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
#elseif os(macOS)
private struct CameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = previewLayer
            setAccessibilityElement(true)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
#endif

enum RecordingMode: String, CaseIterable, Identifiable {
    case audio, video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        }
    }
}

struct RecordMediaAnnotationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSaveLocally: (RecordingMode, URL, String?, String?, String?) async throws -> Void
    let onSaved: () -> Void

    private static let commonLocales = [
        "en-US", "es-ES", "fr-FR", "de-DE", "zh-Hans", "ja-JP",
    ]

    @State private var mode: RecordingMode
    @State private var audioRecorder = AudioRecorder()
    @State private var videoRecorder = VideoRecorder()
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
    @State private var translationUnavailable = false
    #if os(iOS)
    @State private var availableInputs: [AVAudioSessionPortDescription] = []
    @State private var selectedInputUID: String?
    #endif

    init(
        initialMode: RecordingMode,
        onSaveLocally: @escaping (RecordingMode, URL, String?, String?, String?) async throws -> Void,
        onSaved: @escaping () -> Void
    ) {
        self._mode = State(initialValue: initialMode)
        self.onSaveLocally = onSaveLocally
        self.onSaved = onSaved
    }

    private var isRecording: Bool {
        mode == .audio ? audioRecorder.isRecording : videoRecorder.isRecording
    }

    private var hasRecordedFile: Bool {
        (mode == .audio ? audioRecorder.recordedFileURL : videoRecorder.recordedFileURL) != nil
    }

    private var canSave: Bool {
        hasRecordedFile && !isTranscribing && !isSaving
    }

    private var baseLanguageCode: String {
        Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? localeIdentifier
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mode") {
                    Picker("Mode", selection: $mode) {
                        ForEach(RecordingMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(isRecording || hasRecordedFile)
                    .accessibilityIdentifier("recordingModePicker")
                }
                Section("Language") {
                    Picker("Spoken Language", selection: $localeIdentifier) {
                        ForEach(Self.commonLocales, id: \.self) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale) ?? locale).tag(locale)
                        }
                    }
                    .disabled(isRecording || hasRecordedFile)
                    .accessibilityIdentifier("spokenLanguagePicker")
                    if !SpeechTranscriber.supportsOnDeviceRecognition(localeIdentifier: localeIdentifier) {
                        Text("On-device recognition isn't available for this language — transcription will use network recognition instead, and requires an internet connection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                #if os(iOS)
                if mode == .audio, !availableInputs.isEmpty {
                    Section("Microphone") {
                        Picker("Microphone", selection: $selectedInputUID) {
                            ForEach(availableInputs, id: \.uid) { input in
                                Text(input.portName).tag(Optional(input.uid))
                            }
                        }
                        .disabled(audioRecorder.isRecording)
                        .onChange(of: selectedInputUID) { _, newValue in
                            audioRecorder.setPreferredInput(availableInputs.first(where: { $0.uid == newValue }))
                        }
                    }
                }
                #endif
                Section("Recording") {
                    if mode == .video {
                        CameraPreviewView(session: videoRecorder.session)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if isRecording {
                        if mode == .audio {
                            AudioLevelMeterView(level: audioRecorder.audioLevel)
                        }
                        Button("Stop Recording", role: .destructive) {
                            stopAndTranscribe()
                        }
                        .accessibilityIdentifier("stopRecordingButton")
                    } else {
                        Button(hasRecordedFile ? "Record Again" : "Start Recording") {
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
                            .accessibilityIdentifier("mediaTranscriptText")
                        if TranslateGating.shouldOfferTranslation(baseLanguageCode: baseLanguageCode, transcript: transcript, translatedText: translatedText) {
                            Button(isTranslating ? "Translating…" : "Translate to English") {
                                translationUnavailable = false
                                translationConfiguration = TranslationSession.Configuration(
                                    source: Locale.Language(identifier: localeIdentifier),
                                    target: Locale.Language(identifier: "en")
                                )
                            }
                            .disabled(isTranslating)
                            .accessibilityIdentifier("translateButton")
                        }
                        if translationUnavailable {
                            Text("Translation couldn't complete on this device right now.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("translationUnavailableNote")
                        }
                    }
                }
                if !translatedText.isEmpty {
                    Section("English Translation") {
                        Text(translatedText)
                            .accessibilityIdentifier("mediaTranslationText")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(mode == .audio ? "Record Audio Note" : "Record Video Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveMediaAnnotationButton")
                }
            }
        }
        .frame(minWidth: 380, minHeight: 460)
        #if os(iOS)
        .onAppear {
            availableInputs = audioRecorder.availableInputs()
            selectedInputUID = audioRecorder.preferredInput()?.uid
        }
        #endif
        .task(id: mode) {
            guard mode == .video else {
                videoRecorder.stopSession()
                return
            }
            guard await videoRecorder.requestPermission() else {
                errorMessage = "Camera/microphone access was denied."
                isShowingError = true
                return
            }
            do {
                try videoRecorder.startSession()
            } catch {
                errorMessage = error.userFacingMessage
                isShowingError = true
            }
        }
        .onDisappear {
            videoRecorder.stopSession()
        }
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
                translationUnavailable = true
            }
        }
    }

    private func startRecording() async {
        transcript = ""
        translatedText = ""
        onDeviceTranscriptionUnavailable = false
        translationUnavailable = false
        switch mode {
        case .audio:
            guard await audioRecorder.requestPermission() else {
                errorMessage = "Microphone access was denied."
                isShowingError = true
                return
            }
            do {
                try audioRecorder.startRecording()
            } catch {
                errorMessage = error.userFacingMessage
                isShowingError = true
            }
        case .video:
            guard await videoRecorder.requestPermission() else {
                errorMessage = "Camera/microphone access was denied."
                isShowingError = true
                return
            }
            videoRecorder.startRecording()
        }
    }

    private func stopAndTranscribe() {
        isTranscribing = true
        onDeviceTranscriptionUnavailable = false
        Task {
            defer { isTranscribing = false }
            let fileURL: URL?
            switch mode {
            case .audio:
                audioRecorder.stopRecording()
                fileURL = audioRecorder.recordedFileURL
            case .video:
                fileURL = await videoRecorder.stopRecording()
            }
            guard let fileURL else { return }
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
        let fileURL = mode == .audio ? audioRecorder.recordedFileURL : videoRecorder.recordedFileURL
        guard let fileURL else { return }
        isSaving = true
        defer { isSaving = false }
        let vttTranscription = transcriptSegments.isEmpty ? nil : WebVTTFormatter.format(segments: transcriptSegments)
        let vttTranslation: String? = {
            guard !translatedText.isEmpty, let lastSegment = transcriptSegments.last else { return nil }
            return WebVTTFormatter.formatSingleCue(text: translatedText, duration: lastSegment.timestamp + lastSegment.duration)
        }()
        do {
            try await onSaveLocally(mode, fileURL, vttTranscription, vttTranscription == nil ? nil : baseLanguageCode, vttTranslation)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

enum TranslateGating {
    static func shouldOfferTranslation(baseLanguageCode: String, transcript: String, translatedText: String) -> Bool {
        baseLanguageCode != "en" && !transcript.isEmpty && translatedText.isEmpty
    }
}
