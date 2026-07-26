import CupcakeTranscription
import SwiftUI

struct TranscriptionSettingsView: View {
    @AppStorage("cupcake.transcriptionEngineKind") private var engineKindRawValue: String = TranscriptionEngineKind.apple.rawValue

    @State private var availableModelVariants: [String] = []
    @State private var isLoadingModels = false
    @State private var downloadingVariant: String?
    @State private var downloadProgress: Double = 0
    @State private var downloadedVariants: Set<String> = WhisperModelStore.knownDownloadedVariants
    @State private var activeVariant: String = WhisperModelStore.activeModelVariant
    @State private var errorMessage: String?
    @State private var isShowingError = false

    @State private var vocabularyTerms: [TranscriptionVocabularyTerm] = TranscriptionVocabularyStore.allTerms()
    @State private var newTermText = ""

    private var engineKind: Binding<TranscriptionEngineKind> {
        Binding(
            get: { TranscriptionEngineKind(rawValue: engineKindRawValue) ?? .apple },
            set: { engineKindRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Engine", selection: engineKind) {
                    ForEach(TranscriptionEngineKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("transcriptionEnginePicker")
            }

            if engineKind.wrappedValue == .whisperKit {
                Section("WhisperKit Models") {
                    if isLoadingModels {
                        ProgressView("Loading available models…")
                    } else if availableModelVariants.isEmpty {
                        Text("No models found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableModelVariants, id: \.self) { variant in
                            modelRow(for: variant)
                        }
                    }
                }
            }

            Section("Custom Vocabulary") {
                HStack {
                    TextField("Add a term (e.g. cryo-EM, Rab10 GTPase)", text: $newTermText)
                        .accessibilityIdentifier("newVocabularyTermField")
                    Button("Add") {
                        addTerm()
                    }
                    .disabled(newTermText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("addVocabularyTermButton")
                }
                ForEach(vocabularyTerms) { term in
                    HStack {
                        Text(term.text)
                        Spacer()
                        Button {
                            removeTerm(term)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("removeVocabularyTermButton_\(term.text)")
                        .help("Remove Term")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Transcription")
        .task { await loadModelsIfNeeded() }
        .alert("Couldn't complete", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func modelRow(for variant: String) -> some View {
        let isDownloaded = downloadedVariants.contains(variant)
        let isActive = activeVariant == variant
        let isDownloading = downloadingVariant == variant

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(variant)
                if isActive {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .frame(width: 80)
                } else if isDownloaded {
                    Button("Delete") {
                        deleteModel(variant)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("deleteWhisperModelButton_\(variant)")
                    if !isActive {
                        Button("Select") {
                            activeVariant = variant
                            WhisperModelStore.activeModelVariant = variant
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("selectWhisperModelButton_\(variant)")
                    }
                } else {
                    Button("Download") {
                        Task { await downloadModel(variant) }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("downloadWhisperModelButton_\(variant)")
                }
            }
        }
    }

    private func loadModelsIfNeeded() async {
        guard availableModelVariants.isEmpty else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            availableModelVariants = try await WhisperModelStore.fetchAvailableModelVariants()
        } catch {
            errorMessage = "Couldn't load the list of WhisperKit models: \(error.localizedDescription)"
            isShowingError = true
        }
    }

    private func downloadModel(_ variant: String) async {
        downloadingVariant = variant
        downloadProgress = 0
        defer { downloadingVariant = nil }
        do {
            try await WhisperModelStore.download(variant: variant) { progress in
                Task { @MainActor in
                    downloadProgress = progress
                }
            }
            downloadedVariants = WhisperModelStore.knownDownloadedVariants
        } catch {
            errorMessage = "Couldn't download \"\(variant)\": \(error.localizedDescription)"
            isShowingError = true
        }
    }

    private func deleteModel(_ variant: String) {
        WhisperModelStore.markDeleted(variant)
        downloadedVariants = WhisperModelStore.knownDownloadedVariants
    }

    private func addTerm() {
        TranscriptionVocabularyStore.add(newTermText)
        vocabularyTerms = TranscriptionVocabularyStore.allTerms()
        newTermText = ""
    }

    private func removeTerm(_ term: TranscriptionVocabularyTerm) {
        TranscriptionVocabularyStore.remove(id: term.id)
        vocabularyTerms = TranscriptionVocabularyStore.allTerms()
    }
}
