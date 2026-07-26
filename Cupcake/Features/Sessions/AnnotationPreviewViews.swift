import AVKit
import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import CupcakeTranscription
import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

private func fileExtension(from suggestedFilename: String?, fallback: String) -> String {
    guard let suggestedFilename else { return fallback }
    let ext = (suggestedFilename as NSString).pathExtension
    return ext.isEmpty ? fallback : ext
}

private func makeTranscriptVTT(text: String, segments: [TranscriptionSegment], mediaURL: URL) async -> String? {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }
    if !segments.isEmpty {
        return WebVTTFormatter.format(segments: segments)
    }
    let loadedDuration = (try? await AVURLAsset(url: mediaURL).load(.duration))?.seconds ?? 0
    let duration = loadedDuration.isFinite && loadedDuration > 0 ? loadedDuration : 1
    return WebVTTFormatter.formatSingleCue(text: cleaned, duration: duration)
}

private func writeTempFile(_ data: Data, suggestedFilename: String?, fallbackExtension: String) -> URL? {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(fileExtension(from: suggestedFilename, fallback: fallbackExtension))
    guard (try? data.write(to: url)) != nil else { return nil }
    return url
}

private struct DownloadShareButton: View {
    let url: URL

    var body: some View {
        ShareLink(item: url) {
            Image(systemName: "square.and.arrow.up.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, .black.opacity(0.5))
        }
        .accessibilityIdentifier("downloadAnnotationButton")
        .help("Save or Share")
        .padding(6)
    }
}

struct PhotoAnnotationPreview: View {
    let loadData: () async throws -> (data: Data, suggestedFilename: String?)

    @State private var image: PlatformImage?
    @State private var isLoading = true
    @State private var tempFileURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if let tempFileURL { DownloadShareButton(url: tempFileURL) }
                    }
            } else {
                HStack {
                    if isLoading { ProgressView() }
                    Label("Photo note", systemImage: "photo")
                }
            }
        }
        .task {
            defer { isLoading = false }
            guard let result = try? await loadData() else { return }
            image = PlatformImage(data: result.data)
            tempFileURL = writeTempFile(result.data, suggestedFilename: result.suggestedFilename, fallbackExtension: "jpg")
        }
        .onDisappear {
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }
    }
}

func formatMediaTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let totalSeconds = Int(seconds.rounded())
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
}

#if canImport(UIKit)
private final class PlayerLayerPlatformView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlatformVideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerPlatformView {
        let view = PlayerLayerPlatformView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerPlatformView, context: Context) {
        uiView.playerLayer.player = player
    }
}
#elseif canImport(AppKit)
private final class PlayerLayerPlatformView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer = playerLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct PlatformVideoLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerPlatformView {
        let view = PlayerLayerPlatformView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerPlatformView, context: Context) {
        nsView.playerLayer.player = player
    }
}
#endif

@MainActor
@Observable
final class MediaPlayerController {
    var player: AVPlayer?
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var isDraggingSeek = false
    var volume: Float = 1
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?

    func load(url: URL, autoplay: Bool) {
        let newPlayer = AVPlayer(url: url)
        newPlayer.volume = volume
        attachObservers(to: newPlayer)
        player = newPlayer
        if autoplay {
            newPlayer.play()
            isPlaying = true
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seekToCurrentTime() {
        player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
    }

    func setVolume(_ value: Float) {
        volume = value
        player?.volume = value
    }

    func teardown() {
        player?.pause()
        if let player, let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    private func attachObservers(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isDraggingSeek else { return }
                self.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = 0
                player.seek(to: .zero)
            }
        }
        if let item = player.currentItem {
            Task { [weak self] in
                let loadedDuration = (try? await item.asset.load(.duration))?.seconds ?? 0
                if loadedDuration.isFinite, loadedDuration > 0 {
                    self?.duration = loadedDuration
                }
            }
        }
    }
}

struct MediaTransportControls: View {
    var controller: MediaPlayerController

    var body: some View {
        HStack(spacing: 8) {
            Text(formatMediaTime(controller.currentTime))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Slider(
                value: Binding(get: { controller.currentTime }, set: { controller.currentTime = $0 }),
                in: 0...max(controller.duration, 0.1),
                onEditingChanged: { editing in
                    controller.isDraggingSeek = editing
                    if !editing {
                        controller.seekToCurrentTime()
                    }
                }
            )
            .accessibilityIdentifier("mediaAnnotationSeekSlider")
            Text(formatMediaTime(controller.duration))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { controller.volume }, set: { controller.setVolume($0) }),
                in: 0...1
            )
            .frame(width: 60)
            .accessibilityIdentifier("mediaAnnotationVolumeSlider")
        }
    }
}

private enum MediaAnnotationKind {
    case audio
    case video
}

private struct MediaAnnotationPreview: View {
    let kind: MediaAnnotationKind
    var annotationServerID: Int64? = nil
    var transcription: String? = nil
    var translation: String? = nil
    var language: String? = nil
    var refreshTranscription: (() async -> Void)? = nil
    var onUpdateTranscription: ((_ transcription: String?, _ language: String?, _ translation: String?) async throws -> Void)? = nil
    var contextualVocabulary: [String] = []
    let loadData: () async throws -> (data: Data, suggestedFilename: String?)

    @Environment(AppSession.self) private var appSession
    @State private var controller = MediaPlayerController()
    @State private var isLoading = false
    @State private var tempFileURL: URL?
    @State private var isTranscribing = false
    @State private var loadErrorMessage: String?
    @State private var isShowingCaptionEditor = false

    private var noteLabel: String { kind == .audio ? "Audio note" : "Video note" }
    private var mediaWord: String { kind == .audio ? "audio" : "video" }
    private var fallbackExtension: String { kind == .audio ? "m4a" : "mp4" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if kind == .video, let player = controller.player {
                PlatformVideoLayerView(player: player)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if let tempFileURL { DownloadShareButton(url: tempFileURL) }
                    }
            }
            HStack {
                Button {
                    Task { await togglePlayback() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: controller.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playMediaAnnotationButton")
                .help(controller.isPlaying ? "Pause" : "Play")
                if kind == .audio {
                    Image(systemName: "waveform")
                }
                Text(transcription.map(WebVTTFormatter.extractPlainText) ?? noteLabel)
                    .textSelection(.enabled)
                if isTranscribing {
                    ProgressView().controlSize(.small)
                    Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                } else {
                    if transcription == nil, annotationServerID != nil {
                        Text("Awaiting transcription…").font(.caption).foregroundStyle(.secondary)
                    }
                    if onUpdateTranscription != nil {
                        Button {
                            Task { await retranscribe() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Retranscribe on this device")
                        .accessibilityIdentifier("retranscribeMediaAnnotationButton")
                    }
                    if onUpdateTranscription != nil, transcription != nil {
                        Button {
                            isShowingCaptionEditor = true
                        } label: {
                            Image(systemName: "captions.bubble")
                        }
                        .buttonStyle(.plain)
                        .help("Edit Captions")
                        .accessibilityIdentifier("editCaptionsButton")
                    }
                }
                if kind == .audio, let tempFileURL {
                    Spacer()
                    ShareLink(item: tempFileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("downloadAnnotationButton")
                    .help("Save or Share")
                }
            }
            if controller.player != nil {
                MediaTransportControls(controller: controller)
            }
            if let loadErrorMessage {
                Text(loadErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let translation {
                Text(WebVTTFormatter.extractPlainText(from: translation))
                    .font(.caption)
                    .textSelection(.enabled)
            } else if let language {
                Text(language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            if kind == .video {
                await eagerLoadVideo()
            }
        }
        .task(id: annotationServerID) { await observeTranscription() }
        .onDisappear {
            controller.teardown()
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }
        .sheet(isPresented: $isShowingCaptionEditor) {
            if let onUpdateTranscription {
                WebVTTCueEditorView(
                    transcription: transcription,
                    translation: translation,
                    language: language,
                    fallbackExtension: fallbackExtension,
                    loadData: loadData,
                    onSave: onUpdateTranscription
                )
            }
        }
    }

    private func eagerLoadVideo() async {
        isLoading = true
        defer { isLoading = false }
        let result: (data: Data, suggestedFilename: String?)
        do {
            result = try await loadData()
        } catch {
            loadErrorMessage = "Couldn't load video: \(error.userFacingMessage)"
            return
        }
        guard !result.data.isEmpty else {
            loadErrorMessage = "The downloaded video file was empty."
            return
        }
        guard let url = writeTempFile(result.data, suggestedFilename: result.suggestedFilename, fallbackExtension: fallbackExtension) else {
            loadErrorMessage = "Couldn't save the downloaded video to a temporary file."
            return
        }
        tempFileURL = url
        controller.load(url: url, autoplay: false)
    }

    private func togglePlayback() async {
        if controller.player != nil {
            controller.togglePlayback()
            return
        }
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        let result: (data: Data, suggestedFilename: String?)
        do {
            result = try await loadData()
        } catch {
            loadErrorMessage = "Couldn't load \(mediaWord): \(error.userFacingMessage)"
            return
        }
        guard !result.data.isEmpty else {
            loadErrorMessage = "The downloaded \(mediaWord) file was empty."
            return
        }
        guard let url = writeTempFile(result.data, suggestedFilename: result.suggestedFilename, fallbackExtension: fallbackExtension) else {
            loadErrorMessage = "Couldn't save the downloaded \(mediaWord) to a temporary file."
            return
        }
        tempFileURL = url
        controller.load(url: url, autoplay: true)
    }

    private func observeTranscription() async {
        guard let annotationServerID, let refreshTranscription else { return }
        if transcription == nil {
            await refreshTranscription()
        }
        for await event in await appSession.transcriptionEvents() {
            switch event {
            case .started(let id) where id == annotationServerID:
                isTranscribing = true
            case .completed(let id) where id == annotationServerID:
                isTranscribing = false
                await refreshTranscription()
            case .failed(let id, _) where id == annotationServerID:
                isTranscribing = false
            default:
                break
            }
        }
    }

    private func retranscribe() async {
        guard let onUpdateTranscription else { return }
        isTranscribing = true
        defer { isTranscribing = false }
        do {
            let result = try await loadData()
            guard !result.data.isEmpty else {
                loadErrorMessage = "The downloaded \(mediaWord) file was empty."
                return
            }
            guard let url = writeTempFile(result.data, suggestedFilename: result.suggestedFilename, fallbackExtension: fallbackExtension) else {
                loadErrorMessage = "Couldn't save the downloaded \(mediaWord) to a temporary file."
                return
            }
            defer { try? FileManager.default.removeItem(at: url) }
            let engine = TranscriptionEngineFactory.makeEngine()
            let languageCode = language ?? Locale.current.identifier
            let vocabulary = TranscriptionVocabularyStore.currentTexts() + contextualVocabulary
            var transcribed = try await engine.transcribe(fileURL: url, languageCode: languageCode, vocabulary: vocabulary)
            var usedUnprimedFallback = false
            if transcribed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !vocabulary.isEmpty {
                transcribed = try await engine.transcribe(fileURL: url, languageCode: languageCode, vocabulary: [])
                usedUnprimedFallback = !transcribed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard let vtt = await makeTranscriptVTT(text: transcribed.text, segments: transcribed.segments, mediaURL: url) else {
                loadErrorMessage = "Retranscription produced no text, even without vocabulary hints. The recording may be silent, too quiet, or too short."
                return
            }
            try await onUpdateTranscription(vtt, languageCode, nil)
            if usedUnprimedFallback {
                loadErrorMessage = "Vocabulary-primed transcription produced no result, so this used an unprimed fallback instead — jargon terms may be misrecognized. Consider retranscribing again."
            }
        } catch {
            loadErrorMessage = "Couldn't retranscribe: \(error.userFacingMessage)"
        }
    }
}

struct VideoAnnotationPreview: View {
    var annotationServerID: Int64? = nil
    var transcription: String? = nil
    var translation: String? = nil
    var language: String? = nil
    var refreshTranscription: (() async -> Void)? = nil
    var onUpdateTranscription: ((_ transcription: String?, _ language: String?, _ translation: String?) async throws -> Void)? = nil
    var contextualVocabulary: [String] = []
    let loadData: () async throws -> (data: Data, suggestedFilename: String?)

    var body: some View {
        MediaAnnotationPreview(
            kind: .video,
            annotationServerID: annotationServerID,
            transcription: transcription,
            translation: translation,
            language: language,
            refreshTranscription: refreshTranscription,
            onUpdateTranscription: onUpdateTranscription,
            contextualVocabulary: contextualVocabulary,
            loadData: loadData
        )
    }
}

struct AudioAnnotationPreview: View {
    var annotationServerID: Int64? = nil
    let transcription: String?
    let translation: String?
    let language: String?
    var refreshTranscription: (() async -> Void)? = nil
    var onUpdateTranscription: ((_ transcription: String?, _ language: String?, _ translation: String?) async throws -> Void)? = nil
    var contextualVocabulary: [String] = []
    let loadData: () async throws -> (data: Data, suggestedFilename: String?)

    var body: some View {
        MediaAnnotationPreview(
            kind: .audio,
            annotationServerID: annotationServerID,
            transcription: transcription,
            translation: translation,
            language: language,
            refreshTranscription: refreshTranscription,
            onUpdateTranscription: onUpdateTranscription,
            contextualVocabulary: contextualVocabulary,
            loadData: loadData
        )
    }
}

struct CalculatorAnnotationPreview: View {
    let annotationText: String

    private var history: [CalculatorHistoryEntry] {
        (try? JSONDecoder().decode([CalculatorHistoryEntry].self, from: Data(annotationText.utf8))) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Calculator note (\(history.count) calculation\(history.count == 1 ? "" : "s"))", systemImage: "number")
            ForEach(history.suffix(3)) { entry in
                Text("\(CalculatorAnnotationView.formatExpression(entry)) = \(CalculatorAnnotationView.formatNumber(entry.result))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(entry.scratched == true ? 0.5 : 1)
            }
        }
    }
}

struct MolarityCalculatorAnnotationPreview: View {
    let annotationText: String

    private var history: [MolarityHistoryEntry] {
        (try? JSONDecoder().decode([MolarityHistoryEntry].self, from: Data(annotationText.utf8))) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Molarity calculator note (\(history.count) calculation\(history.count == 1 ? "" : "s"))", systemImage: "eyedropper")
            ForEach(history.suffix(3)) { entry in
                Text(MolarityCalculatorAnnotationView.formatExpression(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(entry.scratched == true ? 0.5 : 1)
            }
        }
    }
}

struct SketchAnnotationPreview: View {
    let loadData: () async throws -> (data: Data, suggestedFilename: String?)

    @State private var sketch: SketchData?
    @State private var isLoading = true
    @State private var jsonFileURL: URL?
    @State private var pngFileURL: URL?

    var body: some View {
        Group {
            if let sketch {
                Canvas { context, size in
                    let backgroundColor = Color(hex: sketch.backgroundColor)
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(backgroundColor))
                    SketchRenderer.draw(strokes: sketch.strokes, eraserColor: backgroundColor, in: context)
                }
                .aspectRatio(sketch.width > 0 && sketch.height > 0 ? sketch.width / sketch.height : 1, contentMode: .fit)
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if jsonFileURL != nil || pngFileURL != nil {
                        Menu {
                            if let jsonFileURL {
                                ShareLink("Export as JSON", item: jsonFileURL)
                            }
                            if let pngFileURL {
                                ShareLink("Export as PNG", item: pngFileURL)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .accessibilityIdentifier("downloadAnnotationButton")
                        .help("Export Sketch")
                        .padding(6)
                    }
                }
            } else {
                HStack {
                    if isLoading { ProgressView() }
                    Label("Sketch note", systemImage: "scribble")
                }
            }
        }
        .task {
            defer { isLoading = false }
            guard let result = try? await loadData() else { return }
            sketch = try? JSONDecoder().decode(SketchData.self, from: result.data)
            jsonFileURL = writeTempFile(result.data, suggestedFilename: result.suggestedFilename, fallbackExtension: "json")
            if let sketch {
                pngFileURL = Self.renderPNG(sketch)
            }
        }
        .onDisappear {
            for url in [jsonFileURL, pngFileURL].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func renderPNG(_ sketch: SketchData) -> URL? {
        let width = max(sketch.width, 1)
        let height = max(sketch.height, 1)
        let content = Canvas { context, size in
            let backgroundColor = Color(hex: sketch.backgroundColor)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(backgroundColor))
            SketchRenderer.draw(strokes: sketch.strokes, eraserColor: backgroundColor, in: context)
        }
        .frame(width: width, height: height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width, height: height)

        #if canImport(UIKit)
        guard let uiImage = renderer.uiImage, let pngData = uiImage.pngData() else { return nil }
        #elseif canImport(AppKit)
        guard let nsImage = renderer.nsImage, let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData), let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        #endif

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        guard (try? pngData.write(to: url)) != nil else { return nil }
        return url
    }
}
