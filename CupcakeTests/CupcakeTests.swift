import AVFoundation
import CoreGraphics
import CupcakeModels
import CupcakeTranscription
import SwiftUI
import Testing

@testable import Cupcake

struct CupcakeTests {
    @Test func example() async throws {}

    @Test("StepTemplateRenderer substitutes quantity/scaled_quantity/name/unit placeholders")
    func stepTemplateRendererSubstitutesPlaceholders() {
        let step = CachedProtocolStep(stepDescription: "Add %5.quantity% %5.unit% of %5.name%, scaled: %5.scaled_quantity%.", order: 0)
        let reagent = CachedReagent(serverID: 9, name: "Trypsin", unit: "µL")
        let stepReagent = CachedStepReagent(serverID: 5, stepClientID: step.clientID, reagentClientID: reagent.clientID, quantity: 10, scalable: true, scalableFactor: 2)

        let rendered = StepTemplateRenderer.render(stepDescription: step.stepDescription, reagents: [(stepReagent, reagent)])
        #expect(rendered == "Add 10.0 µL of Trypsin, scaled: 20.0.")
    }

    @Test("StepTemplateRenderer leaves quantity unscaled when the reagent isn't scalable")
    func stepTemplateRendererLeavesUnscaledQuantity() {
        let step = CachedProtocolStep(stepDescription: "%3.scaled_quantity%", order: 0)
        let reagent = CachedReagent(serverID: 1, name: "NaCl", unit: "mg")
        let stepReagent = CachedStepReagent(serverID: 3, stepClientID: step.clientID, reagentClientID: reagent.clientID, quantity: 5, scalable: false, scalableFactor: 3)

        let rendered = StepTemplateRenderer.render(stepDescription: step.stepDescription, reagents: [(stepReagent, reagent)])
        #expect(rendered == "5.0")
    }

    @Test("StepTemplateRenderer leaves unmatched placeholders untouched and skips unsynced step-reagents")
    func stepTemplateRendererSkipsUnsyncedReagents() {
        let step = CachedProtocolStep(stepDescription: "%99.quantity% and %5.quantity%", order: 0)
        let reagent = CachedReagent(name: "Water", unit: "mL")
        let unsyncedStepReagent = CachedStepReagent(stepClientID: step.clientID, reagentClientID: reagent.clientID, quantity: 1)

        let rendered = StepTemplateRenderer.render(stepDescription: step.stepDescription, reagents: [(unsyncedStepReagent, reagent)])
        #expect(rendered == "%99.quantity% and %5.quantity%")
    }

    @Test("UnimodMapping.position falls back to Anywhere for an unrecognized Unimod position string")
    func unimodMappingPositionFallsBack() {
        #expect(UnimodMapping.position(from: "Protein N-term") == "Protein N-term")
        #expect(UnimodMapping.position(from: "Somewhere Unexpected") == "Anywhere")
    }

    @Test("UnimodMapping.modificationType maps known Unimod classifications, and returns nil for unknown ones")
    func unimodMappingModificationTypeMapsClassifications() {
        #expect(UnimodMapping.modificationType(from: "Post-translational") == "Variable")
        #expect(UnimodMapping.modificationType(from: "Chemical derivatization") == "Fixed")
        #expect(UnimodMapping.modificationType(from: "Something else entirely") == nil)
    }

    @Test("SampleIndexTextParser parses comma/range text into sorted unique indices")
    func sampleIndexTextParserParsesRangesAndCommas() {
        #expect(SampleIndexTextParser.parse("1-3, 5") == [1, 2, 3, 5])
        #expect(SampleIndexTextParser.parse("5, 1-3, 2") == [1, 2, 3, 5])
        #expect(SampleIndexTextParser.parse("") == [])
        #expect(SampleIndexTextParser.format([3, 1, 2]) == "1, 2, 3")
    }

    @Test("SketchEditorModel constructs strokes via direct method calls, matching what drag-gesture callbacks would produce")
    func sketchEditorModelConstructsStrokesViaDirectMethodCalls() {
        let model = SketchEditorModel()

        model.selectColor("#FF0000")
        model.appendPoint(CGPoint(x: 0, y: 0))
        model.appendPoint(CGPoint(x: 10, y: 0))
        model.endStroke()
        #expect(model.strokes.count == 1)
        #expect(model.strokes[0].color == "#FF0000")
        #expect(model.strokes[0].points.count == 2)
        #expect(model.strokes[0].width == 4)

        model.selectedWidth = 8
        model.appendPoint(CGPoint(x: 5, y: 5))
        model.appendPoint(CGPoint(x: 5, y: 15))
        model.endStroke()
        #expect(model.strokes.count == 2)
        #expect(model.strokes[1].width == 8)

        model.toggleEraser()
        model.appendPoint(CGPoint(x: 1, y: 1))
        model.appendPoint(CGPoint(x: 2, y: 2))
        model.endStroke()
        #expect(model.strokes[2].color == "eraser")

        // A single-point drag (a tap, not a drag) shouldn't commit a stroke.
        model.appendPoint(CGPoint(x: 50, y: 50))
        model.endStroke()
        #expect(model.strokes.count == 3)

        model.undo()
        #expect(model.strokes.count == 2)

        model.clear()
        #expect(model.isEmpty)
    }

    @Test("SketchEditorModel.buildSketchData/encode produce the reference app's exact JSON vector-stroke schema")
    func sketchEditorModelEncodesExpectedSchema() throws {
        let model = SketchEditorModel()
        model.selectColor("#0000FF")
        model.appendPoint(CGPoint(x: 1, y: 2))
        model.appendPoint(CGPoint(x: 3, y: 4))
        model.endStroke()

        let sketch = model.buildSketchData(size: CGSize(width: 100, height: 200))
        #expect(sketch.width == 100)
        #expect(sketch.height == 200)
        #expect(sketch.backgroundColor == "#ffffff")
        #expect(sketch.strokes.count == 1)
        #expect(sketch.strokes[0].points.map(\.x) == [1, 3])

        let data = try #require(model.encode(size: CGSize(width: 100, height: 200)))
        let decoded = try JSONDecoder().decode(SketchData.self, from: data)
        #expect(decoded.strokes[0].color == "#0000FF")
    }

    @Test("SketchRenderer paints the correct pixel colors for known strokes, verifying the rendered editor image directly rather than by simulating drawing")
    @MainActor
    func sketchRendererPaintsCorrectPixelColors() throws {
        let model = SketchEditorModel()
        model.selectColor("#FF0000")
        model.selectedWidth = 12
        model.appendPoint(CGPoint(x: 10, y: 50))
        model.appendPoint(CGPoint(x: 90, y: 50))
        model.endStroke()

        let size = CGSize(width: 100, height: 100)
        let content = Canvas { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.white))
            SketchRenderer.draw(strokes: model.strokes, eraserColor: .white, in: context)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        let cgImage = try #require(renderer.cgImage)

        let raster = try #require(Self.rasterize(cgImage))
        let onStroke = Self.pixel(raster, x: 50, y: 50)
        let awayFromStroke = Self.pixel(raster, x: 50, y: 5)

        #expect(onStroke.r > 180)
        #expect(onStroke.g < 80)
        #expect(onStroke.b < 80)

        #expect(awayFromStroke.r > 230)
        #expect(awayFromStroke.g > 230)
        #expect(awayFromStroke.b > 230)
    }

    private static func rasterize(_ cgImage: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    /// `(x, y)` in top-left-origin coordinates; flips the row index since `CGContext`'s buffer is bottom-up.
    private static func pixel(_ raster: (pixels: [UInt8], width: Int, height: Int), x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let flippedY = raster.height - 1 - y
        let offset = (flippedY * raster.width + x) * 4
        return (raster.pixels[offset], raster.pixels[offset + 1], raster.pixels[offset + 2], raster.pixels[offset + 3])
    }

    @Test("On-device transcription round-trips real synthesized speech")
    func transcribesRealSynthesizedSpeech() async throws {
        let phrase = "The gloves are on and the sample is ready."
        let fileURL = try await synthesize(phrase, voiceLanguage: "en-US")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await SpeechTranscriber.transcribe(fileURL: fileURL, localeIdentifier: "en-US")
        let transcript = result.text.lowercased()

        #expect(transcript.contains("gloves"))
        #expect(transcript.contains("sample"))
    }

    private func synthesize(_ text: String, voiceLanguage: String) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)

        var audioFile: AVAudioFile?
        var hasResumed = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthesizer.write(utterance) { buffer in
                guard !hasResumed, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                if pcmBuffer.frameLength == 0 {
                    hasResumed = true
                    continuation.resume()
                    return
                }
                do {
                    if audioFile == nil {
                        audioFile = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
                    }
                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
        return outputURL
    }
}
