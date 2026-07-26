import AVKit
import CupcakeNetworking
import CupcakeTranscription
import SwiftUI

struct WebVTTCueEditorView: View {
    let translationAvailable: Bool
    let language: String?
    let fallbackExtension: String
    let loadData: () async throws -> (data: Data, suggestedFilename: String?)
    let onSave: (_ transcription: String?, _ language: String?, _ translation: String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = MediaPlayerController()
    @State private var isLoadingMedia = true
    @State private var tempFileURL: URL?
    @State private var loadErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @State private var editingTarget: EditingTarget = .transcription
    @State private var transcriptionCues: [WebVTTCue]
    @State private var translationCues: [WebVTTCue]

    private enum EditingTarget: String, CaseIterable, Identifiable {
        case transcription = "Transcript"
        case translation = "Translation"
        var id: String { rawValue }
    }

    init(
        transcription: String?,
        translation: String?,
        language: String?,
        fallbackExtension: String,
        loadData: @escaping () async throws -> (data: Data, suggestedFilename: String?),
        onSave: @escaping (_ transcription: String?, _ language: String?, _ translation: String?) async throws -> Void
    ) {
        self.translationAvailable = translation != nil
        self.language = language
        self.fallbackExtension = fallbackExtension
        self.loadData = loadData
        self.onSave = onSave
        _transcriptionCues = State(initialValue: transcription.map(WebVTTFormatter.parse) ?? [])
        _translationCues = State(initialValue: translation.map(WebVTTFormatter.parse) ?? [])
    }

    private var currentCues: Binding<[WebVTTCue]> {
        editingTarget == .transcription ? $transcriptionCues : $translationCues
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if translationAvailable {
                    Picker("Editing", selection: $editingTarget) {
                        ForEach(EditingTarget.allCases) { target in
                            Text(target.rawValue).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding()
                    .accessibilityIdentifier("captionEditingTargetPicker")
                }

                if controller.player != nil {
                    MediaTransportControls(controller: controller)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if isLoadingMedia {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadErrorMessage {
                    Text(loadErrorMessage)
                        .foregroundStyle(.red)
                        .padding()
                } else if currentCues.wrappedValue.isEmpty {
                    ContentUnavailableView("No Captions", systemImage: "captions.bubble", description: Text("There's no \(editingTarget == .transcription ? "transcript" : "translation") to edit yet."))
                } else {
                    List {
                        ForEach(currentCues.wrappedValue.indices, id: \.self) { index in
                            cueRow(index: index)
                        }
                        .onDelete { offsets in
                            currentCues.wrappedValue.remove(atOffsets: offsets)
                        }
                    }
                }

                if let saveErrorMessage {
                    Text(saveErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Edit Captions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("saveCaptionsButton")
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .task {
            await loadMedia()
        }
        .onDisappear {
            controller.teardown()
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }
    }

    @ViewBuilder
    private func cueRow(index: Int) -> some View {
        let binding = currentCues
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    let start = binding.wrappedValue[index].start
                    controller.player?.seek(to: CMTime(seconds: start, preferredTimescale: 600))
                    controller.currentTime = start
                } label: {
                    Text(formatMediaTime(binding.wrappedValue[index].start))
                        .font(.caption2)
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("captionCueSeekButton_\(index)")
                Text("–")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatMediaTime(binding.wrappedValue[index].end))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            TextField("Cue text", text: binding[index].text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("captionCueTextField_\(index)")
        }
    }

    private func loadMedia() async {
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        do {
            let result = try await loadData()
            guard !result.data.isEmpty else {
                loadErrorMessage = "The recording couldn't be loaded."
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fallbackExtension)
            try result.data.write(to: url)
            tempFileURL = url
            controller.load(url: url, autoplay: false)
        } catch {
            loadErrorMessage = "Couldn't load the recording: \(error.userFacingMessage)"
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let newTranscription = transcriptionCues.isEmpty ? nil : WebVTTFormatter.serialize(cues: transcriptionCues)
        let newTranslation = translationCues.isEmpty ? nil : WebVTTFormatter.serialize(cues: translationCues)
        do {
            try await onSave(newTranscription, language, newTranslation)
            dismiss()
        } catch {
            saveErrorMessage = "Couldn't save: \(error.userFacingMessage)"
        }
    }
}
