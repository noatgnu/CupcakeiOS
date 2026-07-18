import CoreGraphics
import CupcakeModels
import CupcakeTranscription
import Speech
import SwiftData
import SwiftUI
import Testing
import Translation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@testable import Cupcake

struct CupcakeTests {
    @Test func example() async throws {}

    @Test("StoredReagentImageProcessor resizes an oversized image to fit within 800x800 and encodes valid PNG base64")
    func storedReagentImageProcessorResizesAndEncodes() throws {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200))
        let oversized = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        }
        let originalData = try #require(oversized.pngData())
        #elseif os(macOS)
        let oversized = NSImage(size: NSSize(width: 1600, height: 1200), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        guard let tiff = oversized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let originalData = bitmap.representation(using: .png, properties: [:]) else {
            Issue.record("couldn't build synthetic test image")
            return
        }
        #endif

        let base64 = try #require(StoredReagentImageProcessor.resizedPNGBase64(from: originalData))
        let resizedData = try #require(Data(base64Encoded: base64))
        let resizedImage = try #require(PlatformImage(data: resizedData))

        #expect(resizedImage.size.width <= 800)
        #expect(resizedImage.size.height <= 800)
        #expect(abs(resizedImage.size.width / resizedImage.size.height - 1600.0 / 1200.0) < 0.01)
    }

    @Test("Apple's Translation framework genuinely translates real Spanish text to English")
    @MainActor
    func translationFrameworkTranslatesRealText() async throws {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: "es-ES"), to: Locale.Language(identifier: "en"))
        guard status == .installed else { return }

        let runner = TranslationHarnessRunner()
        let original = "Buenos días, la muestra está lista para el análisis."
        let result = try await runner.run(text: original, source: "es-ES", target: "en")
        let lowercased = result.lowercased()
        #expect(!result.isEmpty)
        #expect(result != original)
        #expect(lowercased.contains("good") || lowercased.contains("morning") || lowercased.contains("sample") || lowercased.contains("ready") || lowercased.contains("analysis"))
    }

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

    private static func pixel(_ raster: (pixels: [UInt8], width: Int, height: Int), x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let flippedY = raster.height - 1 - y
        let offset = (flippedY * raster.width + x) * 4
        return (raster.pixels[offset], raster.pixels[offset + 1], raster.pixels[offset + 2], raster.pixels[offset + 3])
    }

    @Test("TranslateGating offers translation only for a non-English, non-empty, not-yet-translated transcript")
    func translateGatingOffersTranslationWhenApplicable() {
        #expect(TranslateGating.shouldOfferTranslation(baseLanguageCode: "es", transcript: "hola", translatedText: "") == true)
        #expect(TranslateGating.shouldOfferTranslation(baseLanguageCode: "en", transcript: "hello", translatedText: "") == false)
        #expect(TranslateGating.shouldOfferTranslation(baseLanguageCode: "es", transcript: "", translatedText: "") == false)
        #expect(TranslateGating.shouldOfferTranslation(baseLanguageCode: "es", transcript: "hola", translatedText: "hello") == false)
    }

    @Test("On-device transcription round-trips real synthesized speech")
    func transcribesRealSynthesizedSpeech() async throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

        let fileURL = try Self.writeSynthesizedSpeechFixture()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await SpeechTranscriber.transcribe(fileURL: fileURL, localeIdentifier: "en-US")
        let transcript = result.text.lowercased()

        #expect(transcript.contains("gloves"))
        #expect(transcript.contains("sample"))
    }

    private static func writeSynthesizedSpeechFixture() throws -> URL {
        let data = Data(base64Encoded: synthesizedSpeechFixtureBase64)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try data.write(to: url)
        return url
    }

    private static let synthesizedSpeechFixtureBase64: String = [
        "AAAAHGZ0eXBNNEEgAAAAAE00QSBtcDQyaXNvbQAABAJtb292AAAAbG12aGQAAAAA5n16i+Z9eosAAFYiAAC0AAABAAABAAAAAAAA",
        "AAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAClHRy",
        "YWsAAABcdGtoZAAAAAfmfXqL5n16iwAAAAEAAAAAAAC0AAAAAAAAAAAAAAAAAAEAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAA",
        "AAAAAAAAAEAAAAAAAAAAAAAAAAAAAjBtZGlhAAAAIG1kaGQAAAAA5n16i+Z9eosAAFYiAAC0AAAAAAAAAAAiaGRscgAAAAAAAAAA",
        "c291bgAAAAAAAAAAAAAAAAAAAAAB5m1pbmYAAAAQc21oZAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAA",
        "AAABAAABqnN0YmwAAAB2c3RzZAAAAAAAAAABAAAAZm1wNGEAAAAAAAAAAQAAAAAAAAAAAAIAEAAAAABWIgAAAAAAM2VzZHMAAAAA",
        "A4CAgCIAAAAEgICAFEAUABgAAACaoAAAfQAFgICAAhOIBoCAgAECAAAAD3NidGQAAAAARjMyAAAAGHN0dHMAAAAAAAAAAQAAAC0A",
        "AAQAAAAAKHN0c2MAAAAAAAAAAgAAAAEAAAALAAAAAQAAAAUAAAABAAAAAQAAAMhzdHN6AAAAAAAAAAAAAAAtAAAABAAAANIAAAEB",
        "AAAAlgAAATUAAADkAAAAyAAAANQAAAE8AAABFgAAAQkAAADgAAAAuQAAALAAAAD5AAAAuwAAAMQAAADtAAAA/gAAALUAAAEmAAAA",
        "/wAAAOcAAADYAAAA/wAAALwAAACyAAAAegAAARcAAAC9AAAAxgAAALoAAADJAAAA3gAAAI8AAAC0AAABEgAAAKMAAACiAAAApwAA",
        "AKkAAADNAAAAvAAAAGkAAAAMAAAAJHN0Y28AAAAAAAAABQAAEAAAABl9AAAjAwAAK8YAADOAAAAA+nVkdGEAAADybWV0YQAAAAAA",
        "AAAiaGRscgAAAAAAAAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAAxGlsc3QAAAC8LS0tLQAAABxtZWFuAAAAAGNvbS5hcHBsZS5pVHVu",
        "ZXMAAAAUbmFtZQAAAABpVHVuU01QQgAAAIRkYXRhAAAAAQAAAAAgMDAwMDAwMDAgMDAwMDA4NDAgMDAwMDAzQjYgMDAwMDAwMDAw",
        "MDAwQTgwQSAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAw",
        "MDAwMAAAC9pmcmVlAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACOUbWRhdADQYAcA9L/EPzftIyzq3KQG0VOEwL7PbNvhI3Xf",
        "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",
    ].joined()

    @Test("ReagentPickerField.resolveReagent reuses a tapped suggestion regardless of typed text")
    @MainActor
    func reagentResolutionReusesTappedSuggestion() throws {
        let context = try makeReagentModelContext()
        let existing = CachedReagent(name: "Trypsin", unit: "µL")
        context.insert(existing)

        let resolved = ReagentPickerField.resolveReagent(
            name: "something the user typed instead",
            unit: "mL",
            matchedReagentID: existing.clientID,
            context: context
        )
        #expect(resolved.clientID == existing.clientID)

        let all = try context.fetch(FetchDescriptor<CachedReagent>())
        #expect(all.count == 1)
    }

    @Test("ReagentPickerField.resolveReagent reuses an exact name+unit match even without a tapped suggestion")
    @MainActor
    func reagentResolutionReusesExactMatchWithoutTappedSuggestion() throws {
        let context = try makeReagentModelContext()
        let existing = CachedReagent(name: "Trypsin", unit: "µL")
        context.insert(existing)

        let resolved = ReagentPickerField.resolveReagent(
            name: "trypsin",
            unit: "µL",
            matchedReagentID: nil,
            context: context
        )
        #expect(resolved.clientID == existing.clientID)

        let all = try context.fetch(FetchDescriptor<CachedReagent>())
        #expect(all.count == 1, "Typing an existing reagent's exact name+unit shouldn't create a duplicate")
    }

    @Test("ReagentPickerField.resolveReagent creates a new reagent when no suggestion or exact match exists")
    @MainActor
    func reagentResolutionCreatesNewReagentWhenNoMatchExists() throws {
        let context = try makeReagentModelContext()
        let existing = CachedReagent(name: "Trypsin", unit: "µL")
        context.insert(existing)

        let resolved = ReagentPickerField.resolveReagent(
            name: "Trypsin",
            unit: "mg",
            matchedReagentID: nil,
            context: context
        )
        #expect(resolved.clientID != existing.clientID)
        #expect(resolved.name == "Trypsin")
        #expect(resolved.unit == "mg")

        let all = try context.fetch(FetchDescriptor<CachedReagent>())
        #expect(all.count == 2)
    }

    @MainActor
    private func makeReagentModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CachedReagent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("RichTextHTMLCodec.html returns an empty string for empty content rather than an HTML wrapper")
    func richTextHTMLCodecEmptyContentReturnsEmptyString() {
        #expect(RichTextHTMLCodec.html(from: NSAttributedString(string: "")).isEmpty)
    }

    @Test("RichTextHTMLCodec round-trips bold, italic, and underline formatting through real HTML")
    func richTextHTMLCodecRoundTripsFormatting() throws {
        let attributed = NSMutableAttributedString(string: "Bold Italic Underline")

        #if os(iOS)
        let baseFont = UIFont.systemFont(ofSize: 14)
        let boldFont = UIFont.boldSystemFont(ofSize: 14)
        guard let italicDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) else {
            Issue.record("Couldn't build an italic font descriptor")
            return
        }
        let italicFont = UIFont(descriptor: italicDescriptor, size: 14)
        #elseif os(macOS)
        let baseFont = NSFont.systemFont(ofSize: 14)
        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        #endif

        attributed.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: 4))
        attributed.addAttribute(.font, value: italicFont, range: NSRange(location: 5, length: 6))
        attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 12, length: 9))

        let html = RichTextHTMLCodec.html(from: attributed)
        #expect(html.contains("<"), "Expected real HTML markup, not a plain-text fallback")

        let decoded = try #require(RichTextHTMLCodec.attributedString(from: html))
        #expect(decoded.string.trimmingCharacters(in: .whitespacesAndNewlines) == "Bold Italic Underline")

        let boldRange = (decoded.string as NSString).range(of: "Bold")
        let italicRange = (decoded.string as NSString).range(of: "Italic")
        let underlineRange = (decoded.string as NSString).range(of: "Underline")

        #if os(iOS)
        let decodedBoldFont = decoded.attribute(.font, at: boldRange.location, effectiveRange: nil) as? UIFont
        #expect(decodedBoldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        let decodedItalicFont = decoded.attribute(.font, at: italicRange.location, effectiveRange: nil) as? UIFont
        #expect(decodedItalicFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        #elseif os(macOS)
        let decodedBoldFont = decoded.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        #expect(decodedBoldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let decodedItalicFont = decoded.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        #expect(decodedItalicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #endif

        let decodedUnderline = decoded.attribute(.underlineStyle, at: underlineRange.location, effectiveRange: nil) as? Int
        #expect((decodedUnderline ?? 0) != 0)
    }
}

private struct TranslationHarnessView: View {
    let text: String
    let source: String
    let target: String
    let onResult: (Result<String, Error>) -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .translationTask(configuration) { session in
                do {
                    let response = try await session.translate(text)
                    onResult(.success(response.targetText))
                } catch {
                    onResult(.failure(error))
                }
            }
            .task {
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target)
                )
            }
    }
}

@MainActor
private final class TranslationHarnessRunner {
    #if os(iOS)
    private var window: UIWindow?
    #elseif os(macOS)
    private var window: NSWindow?
    #endif

    func run(text: String, source: String, target: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let view = TranslationHarnessView(text: text, source: source, target: target) { [weak self] result in
                self?.finish(result, continuation: continuation)
            }
            #if os(iOS)
            let hosting = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            window.rootViewController = hosting
            window.isHidden = false
            window.makeKeyAndVisible()
            self.window = window
            #elseif os(macOS)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.setFrame(NSRect(x: -2000, y: -2000, width: 10, height: 10), display: false)
            window.orderFrontRegardless()
            self.window = window
            #endif
        }
    }

    private func finish(_ result: Result<String, Error>, continuation: CheckedContinuation<String, Error>) {
        #if os(iOS)
        window?.isHidden = true
        #elseif os(macOS)
        window?.orderOut(nil)
        #endif
        window = nil
        continuation.resume(with: result)
    }
}
