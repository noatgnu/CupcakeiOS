import AVKit
import CupcakeModels
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

struct VideoAnnotationPreview: View {
    var annotationServerID: Int64? = nil
    var transcription: String? = nil
    var refreshTranscription: (() async -> Void)? = nil
    let loadData: () async throws -> (data: Data, suggestedFilename: String?)

    @Environment(AppSession.self) private var appSession
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var tempFileURL: URL?
    @State private var isTranscribing = false

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        if let tempFileURL { DownloadShareButton(url: tempFileURL) }
                    }
            } else {
                HStack {
                    if isLoading { ProgressView() }
                    Label("Video note", systemImage: "video")
                    if isTranscribing {
                        ProgressView().controlSize(.small)
                        Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            defer { isLoading = false }
            guard let result = try? await loadData() else { return }
            guard let url = writeTempFile(result.data, suggestedFilename: result.suggestedFilename, fallbackExtension: "mp4") else { return }
            tempFileURL = url
            player = AVPlayer(url: url)
        }
        .task(id: annotationServerID) { await observeTranscription() }
        .onDisappear {
            player?.pause()
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }
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
}

struct AudioAnnotationPreview: View {
    var annotationServerID: Int64? = nil
    let transcription: String?
    let translation: String?
    let language: String?
    var refreshTranscription: (() async -> Void)? = nil
    let loadData: () async throws -> (data: Data, suggestedFilename: String?)

    @Environment(AppSession.self) private var appSession
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var tempFileURL: URL?
    @State private var isTranscribing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button {
                    Task { await togglePlayback() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playAudioAnnotationButton")
                Label(transcription.map(WebVTTFormatter.extractPlainText) ?? "Audio note", systemImage: "waveform")
                if isTranscribing {
                    ProgressView().controlSize(.small)
                    Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                }
                if let tempFileURL {
                    Spacer()
                    ShareLink(item: tempFileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("downloadAnnotationButton")
                }
            }
            if let translation {
                Text(WebVTTFormatter.extractPlainText(from: translation))
                    .font(.caption)
            } else if let language {
                Text(language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: annotationServerID) { await observeTranscription() }
        .onDisappear {
            player?.pause()
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }
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

    private func togglePlayback() async {
        if let player {
            if isPlaying {
                player.pause()
            } else {
                player.play()
            }
            isPlaying.toggle()
            return
        }
        isLoading = true
        defer { isLoading = false }
        guard let result = try? await loadData() else { return }
        guard let url = writeTempFile(result.data, suggestedFilename: result.suggestedFilename, fallbackExtension: "m4a") else { return }
        tempFileURL = url
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        newPlayer.play()
        isPlaying = true
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
