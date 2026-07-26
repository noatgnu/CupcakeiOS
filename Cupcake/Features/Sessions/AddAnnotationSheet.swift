import CupcakeModels
import SwiftUI

enum AnnotationKind: String, CaseIterable, Identifiable {
    case text, photo, video, sketch, audio, calculator, molarityCalculator, booking

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "Text"
        case .photo: return "Photo"
        case .video: return "Video"
        case .sketch: return "Sketch"
        case .audio: return "Audio"
        case .calculator: return "Calculator"
        case .molarityCalculator: return "Molarity Calculator"
        case .booking: return "Booking"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .photo: return "photo"
        case .video: return "video"
        case .sketch: return "pencil.and.scribble"
        case .audio: return "mic"
        case .calculator: return "plusminus.circle"
        case .molarityCalculator: return "flask"
        case .booking: return "wrench.and.screwdriver"
        }
    }
}

enum AnnotationScope {
    case step(CachedProtocolStep)
    case session
}

struct AddAnnotationSheet: View {
    let scope: AnnotationScope
    let sessionServerID: Int64?
    let sessionClientID: UUID

    let onSaveText: (String) -> Void
    let onPickPhoto: (Data) -> Void
    let onPickVideo: (Data, String) -> Void
    let onSaveSketch: (Data) -> Void
    let onSaveAudio: (URL, String?, String?, String?) async throws -> Void
    let onSaveVideo: (URL, String?, String?, String?) async throws -> Void
    let onSaveCalculator: (Data) -> Void
    let onSaveMolarityCalculator: (Data) -> Void
    var contextualVocabulary: [String] = []

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: AnnotationKind?
    @State private var textDraft = ""
    @State private var isShowingVideoRecorder = false

    private var availableKinds: [AnnotationKind] {
        switch scope {
        case .session:
            return [.photo, .video, .sketch, .audio]
        case .step(let step):
            var kinds: [AnnotationKind] = [.text, .photo, .video, .sketch, .calculator, .molarityCalculator, .audio]
            if sessionServerID != nil, step.serverID != nil {
                kinds.append(.booking)
            }
            return kinds
        }
    }

    var body: some View {
        Group {
            if isShowingVideoRecorder {
                RecordMediaAnnotationSheet(initialMode: .video, onSaveLocally: saveRecordedMedia, onSaved: { dismiss() }, contextualVocabulary: contextualVocabulary)
            } else {
            switch selectedKind {
            case nil:
                kindPicker
            case .text:
                textForm
            case .photo:
                filePickerScreen(title: "Add Photo") {
                    PhotoAnnotationButton(label: "Choose Photo…") { data in
                        onPickPhoto(data)
                        dismiss()
                    }
                    .accessibilityIdentifier("addPhotoButton")
                }
            case .video:
                filePickerScreen(title: "Add Video") {
                    Button {
                        isShowingVideoRecorder = true
                    } label: {
                        Label("Record Video…", systemImage: "video.fill")
                    }
                    .accessibilityIdentifier("recordVideoButton")
                    VideoAnnotationButton(label: "Choose Video…") { data, fileExtension in
                        onPickVideo(data, fileExtension)
                        dismiss()
                    }
                    .accessibilityIdentifier("addVideoButton")
                }
            case .sketch:
                SketchCanvasView(onSave: { data in
                    onSaveSketch(data)
                    dismiss()
                }, onCancel: { dismiss() })
            case .audio:
                RecordMediaAnnotationSheet(initialMode: .audio, onSaveLocally: saveRecordedMedia, onSaved: { dismiss() }, contextualVocabulary: contextualVocabulary)
            case .calculator:
                CalculatorAnnotationView(onSave: { data in
                    onSaveCalculator(data)
                    dismiss()
                }, onCancel: { dismiss() })
            case .molarityCalculator:
                MolarityCalculatorAnnotationView(onSave: { data in
                    onSaveMolarityCalculator(data)
                    dismiss()
                }, onCancel: { dismiss() })
            case .booking:
                if case .step(let step) = scope, let sessionServerID, let stepServerID = step.serverID {
                    BookInstrumentAnnotationSheet(
                        sessionServerID: sessionServerID,
                        sessionClientID: sessionClientID,
                        stepServerID: stepServerID,
                        stepClientID: step.clientID
                    )
                }
            }
            }
        }
    }

    private var kindPicker: some View {
        NavigationStack {
            List(availableKinds) { kind in
                Button {
                    selectedKind = kind
                } label: {
                    Label(kind.label, systemImage: kind.systemImage)
                }
                .accessibilityIdentifier("annotationKind_\(kind.rawValue)")
            }
            .navigationTitle("Add Annotation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 360)
    }

    private var textForm: some View {
        NavigationStack {
            Form {
                TextField("Note", text: $textDraft, axis: .vertical)
                    .lineLimit(5...10)
                    .accessibilityIdentifier("noteTextField")
            }
            .navigationTitle("Add Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSaveText(textDraft)
                        dismiss()
                    }
                    .disabled(textDraft.isEmpty)
                    .accessibilityIdentifier("saveNoteButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 240)
    }

    private func saveRecordedMedia(mode: RecordingMode, url: URL, transcription: String?, language: String?, translation: String?) async throws {
        switch mode {
        case .audio: try await onSaveAudio(url, transcription, language, translation)
        case .video: try await onSaveVideo(url, transcription, language, translation)
        }
    }

    @ViewBuilder
    private func filePickerScreen<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            List { content() }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 320, minHeight: 200)
    }
}
